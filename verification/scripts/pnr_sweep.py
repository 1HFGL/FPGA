"""同综合网表的Gowin多策略并行PNR。仅写build/pnr_sweep，不晋升正式工程。"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from pathlib import Path
import argparse
import copy
import csv
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'projects/hdmi'))
from build_inputs import source_inputs, write_manifest, prepare_pnr_project
PROJECT = Path('projects/hdmi')
CONFIG_KEYS = ('Place_Option', 'Route_Option', 'Clock_Route_Order')
TABLES = ('3.1.1 Setup Paths Table', '3.1.2 Hold Paths Table',
          '3.1.3 Recovery Paths Table', '3.1.4 Removal Paths Table',
          '3.2 Minimum Pulse Width Table')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def combinations(rules, clock_orders):
    # 永远包含原配置作为同网表对照，不把原有报告当作这轮的baseline。
    result = {(0, 0, 0)}
    for rule in rules:
        pair = rule.split(':')
        if len(pair) != 2 or not all(v.isdigit() for v in pair):
            raise ValueError('Rule must be place:route, e.g. 2:1')
        p, r = map(int, pair)
        if p not in range(5) or r not in range(3):
            raise ValueError('Supported placement=0..4; routing=0..2')
        for c in clock_orders:
            if c not in (0, 1):
                raise ValueError('Clock order must be 0 or 1')
            result.add((p, r, c))
    return sorted(result)


def variant_config(base, strategy):
    config = copy.deepcopy(base)
    p, r, c = strategy
    config.update(Place_Option=str(p), Route_Option=str(r), Clock_Route_Order=c)
    changed = {k for k in base.keys() | config.keys() if base.get(k) != config.get(k)}
    if not changed.issubset(CONFIG_KEYS):
        raise ValueError('Unexpected process configuration change: ' + str(changed))
    return config


def rank_key(result, mode='balanced'):
    if result.get('status') != 'PASS_CURRENT_CONSTRAINTS_ONLY':
        return None
    values = [result.get('slack_ns', {}).get(k, float('nan')) for k in TABLES]
    if not all(math.isfinite(v) and v >= 0 for v in values) or min(values[2:4]) < .100:
        return None
    # balanced先改善五类中最薄余量；同分再看setup/hold。
    return ((min(values), values[0], values[1]) if mode == 'balanced'
            else (values[0], min(values), values[1]))


def command(args, cwd, log, timeout):
    """每路独立OS进程/日志；超时只终止本次派生的进程树。"""
    with log.open('w', encoding='utf-8') as stream:
        proc = subprocess.Popen(list(map(str, args)), cwd=cwd, stdout=stream,
            stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0,
            start_new_session=os.name != 'nt')
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    creationflags=subprocess.CREATE_NO_WINDOW, check=False)
            else:
                import signal
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            raise RuntimeError('Timeout: ' + str(log))
    if code:
        raise RuntimeError(f'Exit {code}: {log}')


def snapshot(source, destination):
    """只复制当前工程的输入，保留相对目录和ROM引用，不复制.git/用户缓存。"""
    source = source.resolve()
    files = [path.relative_to(source) for path in source_inputs(source)]
    hashes = {}
    for rel in sorted(files):
        original, target = source / rel, destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        before = digest(original)
        shutil.copy2(original, target)
        if digest(target) != before or digest(original) != before:
            raise RuntimeError('Input changed during snapshot: ' + str(rel))
        hashes[rel.as_posix()] = before
    return hashes


def input_manifest(trial):
    write_manifest(trial, trial / 'build/hdmi/build_inputs.txt', 'pnr')


def check_pnr_only(trial, log):
    """网表输入工程不一定打印Skip synthesis，按实际输入/读网表日志证明。"""
    active = [n for n in ET.parse(trial / PROJECT / 'piano_hdmi.gprj').findall('.//File')
              if n.get('enable') != '0']
    netlists = [n for n in active if n.get('type') == 'file.netlist']
    if (any(n.get('type') in ('file.verilog', 'file.vhdl') for n in active)
            or len(netlists) != 1
            or netlists[0].get('path') != 'impl/gwsynthesis/piano_hdmi.vg'):
        raise RuntimeError('Expected explicit netlist-only PNR project')
    expected = str((trial / PROJECT / 'impl/gwsynthesis/piano_hdmi.vg').resolve()).replace('\\', '/').lower()
    normalized = log.replace('\\', '/').lower()
    if 'gowinsynthesis start' in normalized or ('reading netlist file: "' + expected + '"') not in normalized:
        raise RuntimeError('Expected explicit netlist-only PNR; implicit synthesis is forbidden')


def prepare_trial(base, trial, strategy, base_config):
    shutil.copytree(base, trial)
    config = variant_config(base_config, strategy)
    write_json(trial / PROJECT / 'process_config.json', config)
    write_json(trial / PROJECT / 'impl/piano_hdmi_process_config.json', config)
    prepare_pnr_project(trial)
    input_manifest(trial)


def run_trial(trial, strategy, args, netlist_hash, base_config):
    started = time.monotonic()
    result = dict(name=trial.name, strategy=dict(zip(('place','route','clock_order'), strategy)),
                  directory=str(trial), status='FAILED')
    out, project = trial / 'build/hdmi', trial / PROJECT
    try:
        command([args.gowin, 'pnr_trial.tcl', 'pnr', *strategy], project, out / 'build.log', args.timeout)
        log = (out / 'build.log').read_text(encoding='utf-8-sig', errors='replace')
        check_pnr_only(trial, log)
        if digest(project / 'impl/gwsynthesis/piano_hdmi.vg') != netlist_hash:
            raise RuntimeError('PNR changed the common synthesis netlist')
        expected = variant_config(base_config, strategy)
        effective = json.loads((project / 'impl/piano_hdmi_process_config.json').read_text(encoding='utf-8-sig'))
        if effective != expected:
            raise RuntimeError('Effective options differ from the declared three-knob strategy')
        pnr = project / 'impl/pnr'
        for suffix in ('.rpt.txt', '_tr_content.html', '.tr'):
            p = pnr / ('piano_hdmi' + suffix)
            if p.exists():
                shutil.copy2(p, out / p.name)
        command([sys.executable, trial / 'projects/piano/read_timing_html.py',
            pnr / 'piano_hdmi_tr_content.html', out / 'timing.txt'], trial, out / 'normalize.log', 60)
        fs = pnr / 'piano_hdmi.fs'
        (out / 'artifact.txt').write_text('file=' + str(fs) + '\nsha256=' + digest(fs) + '\n', encoding='utf-8')
        command([sys.executable, trial / 'verification/scripts/check_hdmi_implementation.py',
            '--directory', out], trial, out / 'check.log', 60)
        checked = json.loads((out / 'implementation_check.json').read_text(encoding='utf-8'))
        result.update(status=checked['status'], slack_ns=checked['worst_reported_slack_ns'],
            resources=checked['resources'], fs=str(fs), fs_sha256=checked['bitstream_sha256'])
        if rank_key(result, args.rank) is None:
            raise RuntimeError('Candidate does not meet the ranking timing gates')
    except Exception as error:
        result.update(status='FAILED', error=str(error))
    result['seconds'] = round(time.monotonic() - started, 3)
    write_json(trial / 'result.json', result)
    return result


def save_results(batch, results, args):
    ordered = sorted(results, key=lambda r: (rank_key(r,args.rank) is not None,
        rank_key(r,args.rank) or (-math.inf,)*3), reverse=True)
    write_json(batch / 'results.json', ordered)
    with (batch / 'results.csv').open('w', newline='', encoding='utf-8-sig') as f:
        writer=csv.writer(f)
        writer.writerow(['name','place','route','clock_order','status','worst','setup','hold','recovery','removal','pulse','seconds','fs_sha256'])
        for r in ordered:
            values=[r.get('slack_ns',{}).get(t,'') for t in TABLES]
            writer.writerow([r['name'],*(r['strategy'].get(k,'') for k in ('place','route','clock_order')),r['status'],
                min(values) if all(isinstance(v,(float,int)) for v in values) else '',
                *values,r['seconds'],r.get('fs_sha256','')])
    return next((r for r in ordered if rank_key(r,args.rank) is not None), None)


def publish_best(batch, best, confirmation, hashes, args, netlist_hash, results):
    """只发布完整且通过门槛的候选；要求确认时，确认本身也是发布门槛。"""
    if rank_key(best, args.rank) is None:
        raise RuntimeError('Selected candidate failed the timing gates')
    if args.confirm_best and (confirmation is None or rank_key(confirmation, args.rank) is None):
        raise RuntimeError('Confirmation failed; results retained but no winner published')
    if confirmation is not None and confirmation['strategy'] != best['strategy']:
        raise RuntimeError('Confirmation strategy differs from selected candidate')
    if any(not (ROOT/rel).is_file() or digest(ROOT/rel) != h for rel,h in hashes.items()):
        raise RuntimeError('Source changed during sweep; results retained but no winner published')
    source = Path(best['directory'])
    files = [(Path(best['fs']), 'piano_hdmi.fs')]
    files += [(source/rel, Path(rel).name) for rel in (
        'build/hdmi/implementation_check.json', 'build/hdmi/timing.txt',
        'projects/hdmi/process_config.json', 'projects/hdmi/effective_options.tcl')]
    if any(not original.is_file() for original,_ in files):
        raise RuntimeError('Candidate artifacts missing; no winner published')
    if digest(Path(best['fs'])) != best['fs_sha256']:
        raise RuntimeError('Candidate bitstream changed; no winner published')
    # 在临时发布目录全部复制成功后才改名，避免缺报告留下半成品best。
    pending = batch/'best_pending'
    pending.mkdir()
    for original,name in files:
        shutil.copy2(original, pending/name)
    write_json(pending/'winner.json',dict(selected=best,netlist_sha256=netlist_hash,
        baseline=next((r for r in results if r['name']=='p0_r0_c0'),None),
        confirmation=confirmation,repeat_matches=(confirmation.get('slack_ns')==best['slack_ns']
            and confirmation.get('resources')==best['resources']) if confirmation else None,
        promoted_to_formal_project=False,programmed=False))
    pending.rename(batch/'best')
    return batch/'best/piano_hdmi.fs'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--jobs',type=int,default=3,choices=range(1,9))
    p.add_argument('--rules',nargs='+',default=['0:0','2:0','2:1','3:1','4:1'])
    p.add_argument('--clock-orders',nargs='+',type=int,choices=(0,1),default=[0])
    p.add_argument('--rank',choices=('balanced','setup'),default='balanced')
    p.add_argument('--gowin',type=Path,default=Path('D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe'))
    p.add_argument('--timeout',type=int,default=1800)
    p.add_argument('--prepare-only',action='store_true')
    p.add_argument('--confirm-best',action='store_true')
    args=p.parse_args()
    strategies=combinations(args.rules,args.clock_orders)
    if not args.gowin.is_file() or args.timeout<1:
        p.error('Missing Gowin executable or invalid timeout')
    batch=ROOT/'build/pnr_sweep'/(datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6])
    batch.mkdir(parents=True,exist_ok=False)
    base=batch/'base'
    hashes=snapshot(ROOT,base)
    write_json(batch/'source_manifest.json',{'source_revision':subprocess.check_output(
        ['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'sha256':hashes,
        'gowin_executable_sha256':digest(args.gowin),'strategies':strategies,'rank':args.rank,'jobs':args.jobs,
        'ranking':'all five nonnegative; recovery/removal >=0.100ns; balanced=max minimum slack, then setup/hold',
        'manual':'SUG1220-2.1E pp36-42; place 0..4, route 0..2, clock order 0/1'})
    print('BATCH '+str(batch),flush=True)
    if args.prepare_only:
        print('PASS source snapshot and strategy validation; no tool run',flush=True)
        return
    project=base/PROJECT
    command([args.gowin,'build.tcl','prepare'],project,batch/'prepare.log',60)
    command([args.gowin,'pnr_trial.tcl','syn',0,0,0],project,batch/'synthesis.log',args.timeout)
    netlist_hash=digest(project/'impl/gwsynthesis/piano_hdmi.vg')
    config=json.loads((project/'process_config.json').read_text(encoding='utf-8-sig'))
    results=[]
    def execute(strategy, name=None):
        trial=batch/'runs'/(name or 'p%d_r%d_c%d'%strategy)
        prepare_trial(base,trial,strategy,config)
        return run_trial(trial,strategy,args,netlist_hash,config)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures=[pool.submit(execute,s) for s in strategies]
        for future in as_completed(futures):
            try:
                r=future.result()
            except Exception as error:
                r={'name':'preparation_error','strategy':{},'status':'FAILED','seconds':0,'error':str(error)}
            results.append(r)
            best=save_results(batch,results,args)
            print(r['name']+' '+r['status']+' '+str(r.get('slack_ns',r.get('error'))),flush=True)
    best=save_results(batch,results,args)
    if not best:
        raise SystemExit('No passing candidate; see '+str(batch/'results.json'))
    confirmation=None
    if args.confirm_best:
        confirmation=execute(tuple(best['strategy'].values()),'confirm_'+best['name'])
        write_json(batch/'confirmation.json',confirmation)
        print('CONFIRM '+confirmation['status'],flush=True)
    try:
        destination=publish_best(batch,best,confirmation,hashes,args,netlist_hash,results)
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
    print('BEST '+str(destination),flush=True)


if __name__=='__main__':
    main()
