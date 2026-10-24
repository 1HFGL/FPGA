"""节拍局部优化：冻结当前工作区参考，逐拍差分和故障注入；旧代码只放 build。"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/regression/audio_timing'
BIN = Path('C:/Library/modelsim/win64')
MODULES = {'rtl/audio/sample_tick.v': 'sample_tick', 'rtl/audio/i2s_tx.v': 'i2s_tx',
           'rtl/control/event_encoder.v': 'event_encoder'}
REFERENCE_REVISION = '922e059d14fdf09c07c80f3562ffd678fd23dac8'
TB = ROOT / 'verification/tb/integration/tb_audio_timing_equivalence.v'
EVENT_TB = ROOT / 'verification/tb/integration/tb_event_selection_equivalence.v'


def reference_sources():
    # 此三个模块在本轮前与固定Git版本相同。新checkout也能重建参考，
    # 不能在优化后用当前源码生成一个同样被优化的“旧版”来假做差分。
    paths=[]
    for rel, name in MODULES.items():
        original=subprocess.check_output(['git','show',REFERENCE_REVISION+':'+rel],cwd=ROOT).decode('utf-8-sig')
        body,count=re.subn(r'\bmodule\s+'+name+r'\b','module '+name+'_before',original,count=1)
        if count!=1:raise SystemExit('Reference module missing: '+rel)
        target=OUT/(name+'_before.v')
        if target.exists():
            if target.read_text(encoding='utf-8-sig')!=body:
                raise SystemExit('Frozen reference differs from pinned Git: '+rel)
        else:target.write_text(body,encoding='utf-8')
        paths.append(target)
    return paths


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def snapshot():
    OUT.mkdir(parents=True, exist_ok=True)
    if (OUT / 'baseline.json').exists():
        raise SystemExit('Baseline exists; refusing to overwrite the before-change evidence')
    protected = [p for folder in ('upstream', 'boards', 'verification/tb')
                 for p in (ROOT / folder).rglob('*') if p.is_file() and p not in (TB,EVENT_TB)]
    protected += list((ROOT / 'projects').glob('*/process_config.json'))
    protected += [ROOT / '.vscode/config.json']
    inputs = [p for folder in ('rtl', 'projects') for p in (ROOT / folder).rglob('*')
              if p.is_file() and p.suffix in ('.v', '.gprj', '.tcl', '.json', '.mem')
              and 'impl' not in p.parts]
    data = dict(head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                basis='current working tree, including previous uncommitted optimization',
                protected_sha256={p.relative_to(ROOT).as_posix(): sha(p) for p in protected},
                input_sha256={p.relative_to(ROOT).as_posix(): sha(p) for p in inputs}, references={})
    for target in reference_sources():
        data['references'][target.name] = sha(target)
    for tag, folder in [('hdmi_default', ROOT/'build/hdmi'), ('piano_default', ROOT/'build/piano'),
                        ('hdmi_best', ROOT/'build/pnr_sweep/20261017_210227_e84131/best')]:
        dest = OUT / 'before' / tag
        dest.mkdir(parents=True, exist_ok=True)
        for p in folder.glob('*'):
            if p.is_file() and p.suffix in ('.txt', '.html', '.json', '.fs'):
                shutil.copy2(p, dest / p.name)
    save(OUT / 'baseline.json', data)
    print('PASS current-worktree audio timing baseline saved', flush=True)


def run(mutation=None, event=False):
    base = json.loads((OUT / 'baseline.json').read_text(encoding='utf-8'))
    for rel, expected in base['references'].items():
        if sha(OUT / rel) != expected:
            raise SystemExit('Reference changed: ' + rel)
    for rel, expected in base['protected_sha256'].items():
        if sha(ROOT / rel) != expected:
            raise SystemExit('Protected file changed: ' + rel)
    sources = [ROOT / rel for rel in MODULES]
    tag = ('event_equivalence' if event else 'equivalence') + ('_' + mutation if mutation else '')
    if mutation:
        # 只在临时编译源中打坏阈值或帧边界，不能改正式RTL/队友TB。
        options={'threshold':(0,'phase_acc >= PHASE_THRESHOLD','phase_acc > PHASE_THRESHOLD'),
                 'serial':(1,'bit_index == SLOT_BITS - 1','bit_index == SLOT_BITS - 2'),
                 'priority':(2,'offset>=rr_key','offset>rr_key')}
        index,before,after=options[mutation]
        target=sources[index]
        body = target.read_text(encoding='utf-8')
        if body.count(before) != 1:
            raise SystemExit('Ambiguous mutation target: ' + before)
        mutant = OUT / (tag + '.v')
        mutant.write_text(body.replace(before, after), encoding='utf-8')
        sources = [mutant if p == target else p for p in sources]
    sources += reference_sources()
    sources += [EVENT_TB if event else TB]
    top='tb_event_selection_equivalence' if event else 'tb_audio_timing_equivalence'
    lib = OUT / (tag + '_work')
    lib_arg = lib.relative_to(ROOT).as_posix()
    commands = [('vlib', [lib_arg])] if not (lib / '_info').exists() else []
    commands += [('vlog', ['-vlog01compat', '-pedanticerrors', '-work', lib_arg, *map(str, sources)]),
                 ('vsim', ['-c', '-lib', lib_arg, top,
                           '-wlf', str(OUT/(tag+'.wlf')), '-do',
                           'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f'])]
    for tool, args in commands:
        log = OUT / (tag + '_' + tool + '.log')
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run([str(BIN/(tool+'.exe')), *args], cwd=ROOT,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=180)
        body = log.read_text(errors='replace')
        if tool != 'vsim' and (result.returncode or re.search(r'\*\* (Error|Fatal):', body)):
            raise SystemExit(body[-4000:])
    expected = {'threshold':'FAIL audio tick mismatch','serial':'FAIL audio serial mismatch',
                'priority':'FAIL event selection mismatch'}[mutation] if mutation else 'PASS '+top
    if expected not in body or (mutation and 'PASS '+top in body):
        raise SystemExit('Missing expected checker: ' + expected + '\n' + body[-4000:])
    if not mutation and (result.returncode or re.search(r'\bFAIL\b|\*\* (Error|Fatal):', body)):
        raise SystemExit(body[-4000:])
    save(OUT / (tag + '_result.json'), dict(status='EXPECTED_FAULT_REJECTED' if mutation else 'PASS',
         marker=expected, flags='-vlog01compat -pedanticerrors',
         source_sha256={str(p.relative_to(ROOT)): sha(p) for p in [*sources, Path(__file__).resolve()]},
         protected_count=len(base['protected_sha256']), log=str(log.relative_to(ROOT))))
    print('\n'.join(line for line in body.splitlines() if expected in line), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', action='store_true')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--event', action='store_true')
    parser.add_argument('--mutation', choices=('threshold', 'serial', 'priority'))
    args = parser.parse_args()
    if args.snapshot:
        snapshot()
    if args.run or args.mutation or args.event:
        run(args.mutation, args.event or args.mutation=='priority')
