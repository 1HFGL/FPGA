"""汇总本轮无损架构修改的真实证据，校验输入身份和原始受保护文件。"""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
import sys
from pnr_sweep import TABLES, digest

ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'build/regression/architecture'
OUT=ROOT/'verification/evidence/architecture'


def require(condition, message):
    if not condition:
        raise SystemExit('FAIL architecture audit: '+message)


def verify_text_manifest(path):
    count=0
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        match=re.fullmatch(r'([a-fA-F0-9]{64})  (.+)',line)
        if match:
            source=Path(match[2])
            if not source.is_absolute():source=ROOT/source
            require(source.is_file() and digest(source)==match[1].lower(), 'stale dependency '+str(source))
            count+=1
    require(count>20, 'incomplete manifest '+str(path))
    return count


def verify_json_manifest(path):
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    require(data['flags']=='-vlog01compat -pedanticerrors','non-Verilog compilation')
    for name,expected in data['sha256'].items():
        source=Path(name)
        if not source.is_absolute():source=ROOT/source
        require(source.is_file() and digest(source)==expected, 'stale dependency '+str(source))
    return len(data['sha256'])


def test_record(folder, name, marker, json_manifest=True):
    log=folder/(name+('_console.log' if folder==BUILD else '.log'))
    body=log.read_text(errors='replace')
    require(marker in body, 'missing test completion '+name)
    if not marker.startswith('FAIL '):
        require(not re.search(r'\bFAIL\b|\*\* (Error|Fatal):',body), 'failed test '+name)
    inputs=folder/(name+'_inputs.json')
    dependencies=verify_json_manifest(inputs) if json_manifest else 0
    return {'log':str(log.relative_to(ROOT)), 'log_sha256':digest(log),
            'input_manifest':str(inputs.relative_to(ROOT)), 'input_manifest_sha256':digest(inputs),
            'dependencies':dependencies,'result':[line for line in body.splitlines() if marker in line]}


def implementation(report, timing, fs):
    body=report.read_text(encoding='utf-8-sig')
    times=timing.read_text(encoding='utf-8-sig')
    resources={}
    for name in ('Logic','Register','BSRAM','DSP'):
        match=re.search(rf'(?m)^\s*{name}\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',body)
        require(match is not None,'missing resource '+name)
        resources[name]=float(match[1])
    slacks={}
    for section in TABLES:
        table=times.split(section,1)[1].strip().split('\n\n',1)[0] if section in times else ''
        values=[float(x) for x in re.findall(r'(?m)^\s*\d+\s+(-?\d+\.\d+)\s+',table)]
        require(bool(values) and min(values)>=0,'missing/negative timing '+section)
        slacks[section]=min(values)
    return {'resources':resources,'slack_ns':slacks,'bitstream':str(fs.relative_to(ROOT)),
            'bitstream_sha256':digest(fs),'report_sha256':digest(report),'timing_sha256':digest(timing)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sweep',type=Path,required=True)
    args=parser.parse_args()
    args.sweep=args.sweep.resolve()
    baseline=json.loads((BUILD/'baseline.json').read_text())
    for name,module in [('rtl/synth/voice_bank_music_pipe.v','voice_bank_music_pipe'),
                        ('rtl/display/instrument_panel_ui.v','instrument_panel_ui')]:
        original=subprocess.check_output(['git','show',baseline['revision']+':'+name],cwd=ROOT).decode('utf-8-sig')
        original=re.sub(r'\bmodule\s+'+module+r'\b','module '+module+'_original',original,count=1)
        actual=(BUILD/(module+'_original.v')).read_text(encoding='utf-8-sig')
        require(actual.replace('\r\n','\n')==original.replace('\r\n','\n'),'temporary reference differs from pinned Git '+name)
    for name,expected in baseline['protected_sha256'].items():
        require(digest(ROOT/name)==expected,'protected input changed '+name)
    deltas=json.loads((ROOT/'verification/data/upstream_modifications.json').read_text())
    require(len(deltas)==1 and deltas[0]['path']=='rtl/synth/voice_bank_music_pipe.v','unexpected imported RTL authorization')
    changes={entry['path']:entry for entry in deltas}
    for entry in json.loads((ROOT/'verification/data/upstream_imports.json').read_text(encoding='utf-8-sig')):
        change=changes.get(entry['path'])
        expected=entry['sha256'].lower()
        if change:
            require(change['upstream_sha256']==expected,'upstream provenance was replaced')
            expected=change['current_sha256']
        require(digest(ROOT/entry['path'])==expected,'unregistered upstream change '+entry['path'])
    strict=verify_text_manifest(ROOT/'build/regression/strict/strict_inputs.txt')
    tests={}
    for top in ('tb_modal_parameter_rom','tb_architecture_equivalence','tb_architecture_ui','tb_architecture_startup'):
        tests[top]=test_record(BUILD,top,'PASS '+top)
    tests['rom_mutation']=test_record(BUILD,'tb_modal_parameter_rom_mutation','FAIL modal ROM value')
    final=ROOT/'build/regression/final'
    for top in ('tb_final_modal_adapter','tb_final_env_alignment','tb_simple_display_frames',
                'tb_performance_octaves','tb_hdmi_octaves','tb_final_wave_envelope','tb_final_performance_legacy'):
        tests[top]=test_record(final,top,'PASS '+top.removesuffix('_legacy'))
    # 此旧TB固定要求错误的启动显示8；明确记录不兼容，不能把失败删掉或冒充通过。
    tests['obsolete_startup_assertion']=test_record(final,'tb_final_hdmi_isolation','FAIL final display startup gain')
    music=ROOT/'build/regression/music'
    for top in ('tb_music_protocol','tb_music_pipe','tb_music_uart16','tb_music_display_isolation',
                'tb_music_controls','tb_music_local_controls','tb_music_recovery'):
        tests[top]=test_record(music,top,'PASS '+top)
    oracle=json.loads((music/'tb_music_pipe.verification.json').read_text())
    require(oracle['sixteen_voice_bit_exact'] and oracle['four_voice_reference_exact'] and oracle['legacy_golden_exact'],
            'independent oracle did not pass')
    reset=ROOT/'build/regression/hdmi_reset'
    for mode,marker in [('normal','PASS tb_review_hdmi_reset_recovery'),('negative','FAIL HDMI reset word alignment epoch=1')]:
        verify_text_manifest(reset/(mode+'_inputs.txt'))
        log=reset/('tb_review_hdmi_reset_recovery_'+mode+'.log')
        body=log.read_text(errors='replace')
        require(marker in body,'missing HDMI recovery evidence '+mode)
        tests['hdmi_reset_'+mode]={'log_sha256':digest(log),'result':[line for line in body.splitlines() if marker in line]}
    hdmi=json.loads((ROOT/'build/hdmi/implementation_check.json').read_text())
    require(hdmi['status']=='PASS_CURRENT_CONSTRAINTS_ONLY','HDMI implementation failed')
    for item in hdmi['inputs']:
        require(digest(Path(item['path']))==item['sha256'],'stale HDMI input')
    verify_text_manifest(ROOT/'build/piano/build_inputs.txt')
    builds={}
    for name,base,timing in [('hdmi','piano_hdmi',ROOT/'build/hdmi/timing.txt'),
                             ('piano','piano_performance',ROOT/'build/piano/timing_from_html.txt')]:
        pnr=ROOT/'projects'/name/'impl/pnr'
        builds[name]=implementation(pnr/(base+'.rpt.txt'),timing,pnr/(base+'.fs'))
        old_report=BUILD/('baseline_'+base+'.rpt.txt')
        if old_report.exists():
            before=old_report.read_text(encoding='utf-8-sig')
            old_bsram=int(re.search(r'BSRAM\s*\|\s*(\d+)/',before)[1])
        else:
            # 新克隆没有旧impl时，只引用已发布的旧基线记录，不读取当前报告冒充旧版。
            recorded=json.loads((OUT/'summary.json').read_text(encoding='utf-8'))
            require(recorded['baseline_revision']==baseline['revision'],'missing matching resource baseline')
            old_bsram=recorded['builds'][name]['baseline_bsram']
        require(builds[name]['resources']['BSRAM']<old_bsram,'ROM optimization did not reduce BSRAM '+name)
        builds[name]['baseline_bsram']=old_bsram
    winner=json.loads((args.sweep/'best/winner.json').read_text())
    selected=winner['selected'];confirmation=winner['confirmation']
    require(selected['status']==confirmation['status']=='PASS_CURRENT_CONSTRAINTS_ONLY','candidate confirmation failed')
    require(digest(args.sweep/'best/piano_hdmi.fs')==selected['fs_sha256'],'candidate identity mismatch')
    sweep_source=json.loads((args.sweep/'source_manifest.json').read_text())
    for name,expected in sweep_source['sha256'].items():
        require(digest(ROOT/name)==expected,'candidate source changed '+name)
    reference_digest=digest(BUILD/'voice_bank_music_pipe_original.v')
    for script in ('test_modal_rom_packing.py','test_pnr_sweep.py'):
        path=ROOT/'verification/scripts'/script
        result=subprocess.run([sys.executable,str(path)],cwd=ROOT,text=True,capture_output=True)
        log=BUILD/(path.stem+'.log');log.write_text(result.stdout+result.stderr,encoding='utf-8')
        require(result.returncode==0,'unit test failed '+script)
        tests[path.stem]={'log_sha256':digest(log),'script_sha256':digest(path),'exit_code':result.returncode}
    # 当前RTL/ROM和工程输入的身份都进入摘要；文档改写不会伪造新实现证据。
    sources=[*ROOT.glob('rtl/**/*.v'),*ROOT.glob('rtl/rom/*.mem'),
             *ROOT.glob('projects/*/*.gprj'),ROOT/'verification/scripts/check_modal_rom.tcl',
             ROOT/'model/pack_modal_rom.py',Path(__file__).resolve(),
             ROOT/'verification/data/upstream_modifications.json']
    summary={'date':'2026-10-17','baseline_revision':baseline['revision'],
        'protected_inputs_unchanged':len(baseline['protected_sha256']), 'strict_files':strict,
        'upstream_modifications':deltas,'temporary_reference_sha256':reference_digest,
        'source_sha256':{p.relative_to(ROOT).as_posix():digest(p) for p in sources},
        'tests':tests,'independent_oracle':oracle,'builds':builds,
        'hdmi_sweep':{'batch':str(args.sweep.relative_to(ROOT)),'winner':winner,
                      'all_results':json.loads((args.sweep/'results.json').read_text())},
        'known_test_contract_change':'tb_final_hdmi_isolation asserts startup display8; tb_architecture_startup covers default127 plus full16 formal audio isolation across HPD/PLL/pixel-stop; tb_hdmi_octaves and 17 recovery epochs also pass',
        'programmed':False,'pushed':False,
        'limitations':['PR1014 remains','DAC complete external timing unresolved',
                       'HDMI board electrical budget/hardware not signed off','USB touch not integrated','End-to-end latency unmeasured']}
    OUT.mkdir(parents=True,exist_ok=True)
    shutil.copy2(BUILD/'baseline.json',OUT/'baseline.json')
    (OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'PASS architecture audit: {len(tests)} evidence entries, {strict} strict files, {len(baseline["protected_sha256"])} protected inputs unchanged; hardware pending')


if __name__=='__main__':
    main()
