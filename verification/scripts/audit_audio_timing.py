"""审计音频节拍/事件选择局部优化，区分同策略对照和布局候选，不冒充实物验收。"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil

from audit_architecture import implementation, verify_text_manifest, verify_json_manifest, test_record
from run_audio_timing_tests import REFERENCE_REVISION, reference_sources

ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'build/regression/audio_timing'
OUT=ROOT/'verification/evidence/datapath'
CHANGES={'rtl/audio/sample_tick.v','rtl/audio/i2s_tx.v','rtl/control/event_encoder.v',
         'rtl/display/instrument_panel_ui.v'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(test,message):
    if not test:raise SystemExit('FAIL datapath audit: '+message)


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sweep',type=Path,required=True)
    args=parser.parse_args()
    sweep=args.sweep.resolve()
    baseline=load(BUILD/'baseline.json')
    protected=baseline['protected_sha256']
    for rel,expected in protected.items():
        require(sha(ROOT/rel)==expected,'protected file '+rel)
    changed=[]
    for rel,expected in baseline['input_sha256'].items():
        if sha(ROOT/rel)!=expected:changed.append(rel)
    require(set(changed)==CHANGES,'unexpected input changes '+str(changed))
    verify_text_manifest(ROOT/'build/regression/strict/strict_inputs.txt')
    tests={}
    for tag in ('equivalence','event_equivalence','equivalence_threshold','equivalence_serial','event_equivalence_priority'):
        data=load(BUILD/(tag+'_result.json'))
        for rel,expected in data['source_sha256'].items():
            require(sha(ROOT/rel)==expected,'stale local test '+tag+': '+rel)
        log=ROOT/data['log']
        require(data['marker'] in log.read_text(errors='replace'),'missing local test '+tag)
        tests[tag]=dict(result=data['status'],marker=data['marker'],log=data['log'],log_sha256=sha(log))
    regressions=['sample_tick_tb','synth_top_tb','tb_audio_boundaries','tb_final_modal_adapter',
                 'tb_final_env_alignment','tb_performance_octaves','tb_hdmi_octaves','tb_simple_display_frames']
    for name in regressions:
        directory=ROOT/'build/regression/final'
        verify_json_manifest(directory/(name+'_inputs.json'))
        body=(directory/(name+'_console.log')).read_text(errors='replace')
        marker='PASS '+name
        require(marker in body and 'FAIL' not in body,'failed regression '+name)
        tests[name]=dict(result='PASS',log=str((directory/(name+'_console.log')).relative_to(ROOT)),
                        log_sha256=sha(directory/(name+'_console.log')),
                        marker=[line for line in body.splitlines() if marker in line])
    startup=ROOT/'build/regression/architecture'
    verify_json_manifest(startup/'tb_architecture_startup_inputs.json')
    startup_log=startup/'tb_architecture_startup_console.log'
    require('PASS tb_architecture_startup' in startup_log.read_text(errors='replace'),'startup missing')
    tests['tb_architecture_startup']=dict(result='PASS',log=str(startup_log.relative_to(ROOT)),log_sha256=sha(startup_log))
    tests['tb_architecture_ui']=test_record(startup,'tb_architecture_ui','PASS tb_architecture_ui')
    music=ROOT/'build/regression/music'
    for name in ('tb_music_protocol','tb_music_pipe','tb_music_uart16','tb_music_display_isolation',
                 'tb_music_controls','tb_music_local_controls','tb_music_recovery'):
        tests[name]=test_record(music,name,'PASS '+name)
    oracle=load(music/'tb_music_pipe.verification.json')
    require(oracle['sixteen_voice_bit_exact'] and oracle['four_voice_reference_exact'] and oracle['legacy_golden_exact'],
            'independent music oracle')
    tests['independent_oracle']=oracle
    controls=ROOT/'build/regression/logs'
    # C脚本的输入清单少于整机，不复用要求至少20份文件的整机清单检查器。
    control_inputs=0
    for line in (controls/'C_sha256.txt').read_text(encoding='utf-8-sig').splitlines():
        if len(line)>66 and line[64:66]=='  ':
            require(sha(ROOT/line[66:])==line[:64].lower(),'stale C input '+line[66:])
            control_inputs+=1
    require(control_inputs==9,'unexpected C manifest size')
    for name in ('tb_input_sync_debounce','tb_event_encoder','tb_voice_allocator','tb_allocator_age',
                 'tb_allocator_owner','tb_allocator_expression_owner','tb_allocator_expression_reset'):
        log=controls/(name+'.log')
        body=log.read_text(errors='replace')
        require('PASS' in body and 'FAIL' not in body,'failed C regression '+name)
        tests[name]=dict(result='PASS',log=str(log.relative_to(ROOT)),log_sha256=sha(log))
    reset=ROOT/'build/regression/hdmi_reset'
    for mode,marker in [('normal','PASS tb_review_hdmi_reset_recovery'),
                        ('negative','FAIL HDMI reset word alignment epoch=1')]:
        verify_text_manifest(reset/(mode+'_inputs.txt'))
        log=reset/('tb_review_hdmi_reset_recovery_'+mode+'.log')
        require(marker in log.read_text(errors='replace'),'HDMI recovery '+mode)
        tests['hdmi_reset_'+mode]=dict(marker=marker,log_sha256=sha(log))
    parameter_dir=ROOT/'build/regression/audio-parameters'
    with (parameter_dir/'summary.csv').open(encoding='utf-8-sig',newline='') as f:
        cases=list(csv.DictReader(f))
    require(len(cases)==15,'parameter cases incomplete')
    for row in cases:
        case=int(row['case'])
        require(row['verdict']==('accepted' if case in (0,1,14) else 'explicitly_rejected'),'parameter verdict')
        log=parameter_dir/('case'+str(case))/'simulation.log'
        require(log.exists(),'missing parameter log')
        for line in (log.parent/'inputs.txt').read_text(encoding='utf-8-sig').splitlines():
            if len(line)>66 and line[64:66]=='  ':
                require(sha(Path(line[66:]))==line[:64].lower(),'stale parameter source')
    tests['parameter_guard']=dict(accepted=3,explicitly_rejected=12)
    verify_text_manifest(ROOT/'build/hdmi/build_inputs.txt')
    checked=load(ROOT/'build/hdmi/implementation_check.json')
    require(checked['status']=='PASS_CURRENT_CONSTRAINTS_ONLY','formal HDMI check')
    hdmi=implementation(ROOT/'build/hdmi/piano_hdmi.rpt.txt',ROOT/'build/hdmi/timing.txt',
                        ROOT/'projects/hdmi/impl/pnr/piano_hdmi.fs')
    for rel,expected in load(sweep/'source_manifest.json')['sha256'].items():
        require(sha(ROOT/rel)==expected,'stale sweep '+rel)
    winner=load(sweep/'best/winner.json')
    require(winner['repeat_matches'] is True,'candidate confirmation differs')
    require(sha(sweep/'best/piano_hdmi.fs')==winner['selected']['fs_sha256'],'candidate hash')
    # 旧报告只有其完整构建输入与本轮冻结基线一致，才允许作为数值对照。
    before=BUILD/'before'
    for kind in ('hdmi_default','piano_default'):
        for line in (before/kind/'build_inputs.txt').read_text(encoding='utf-8-sig').splitlines():
            if len(line)>66 and line[64:66]=='  ':
                source=Path(line[66:])
                rel=source.relative_to(ROOT).as_posix()
                expected=baseline['input_sha256'].get(rel,protected.get(rel))
                require(line[:64].lower()==(expected or sha(source)),'baseline identity '+rel)
    before_hdmi=load(before/'hdmi_default/implementation_check.json')
    before_piano=load(ROOT/'verification/evidence/architecture/summary.json')['builds']['piano']
    require(sha(before/'piano_default/piano_performance.rpt.txt')==before_piano['report_sha256'],
            'before piano report differs from preceding audit')
    require(sha(before/'piano_default/timing_from_html.txt')==before_piano['timing_sha256'],
            'before piano timing differs from preceding audit')
    before_best=load(before/'hdmi_best/winner.json')
    OUT.mkdir(parents=True,exist_ok=True)
    evidence=dict(date='2026-10-18',reference_revision=REFERENCE_REVISION,
        audit_sha256=sha(Path(__file__).resolve()),baseline_sha256=sha(BUILD/'baseline.json'),
        basis=baseline['basis'],changed_rtl=changed,protected_inputs_unchanged=len(protected),
        strict_files=sum(1 for line in (ROOT/'build/regression/strict/strict_inputs.txt').read_text(encoding='utf-8-sig').splitlines() if len(line)>66 and line[64:66]=='  '),
        source_sha256={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'rtl').rglob('*.v')},
        references={p.name:sha(p) for p in reference_sources()},tests=tests,
        before=dict(hdmi_default=before_hdmi,piano_default=before_piano,hdmi_best=before_best['selected']),
        after=dict(hdmi_default=hdmi,hdmi_best=winner['selected']),
        release_entry='projects/hdmi/piano_hdmi.gprj / piano_hdmi_top only; no separate headless release',
        retired_entry='piano_performance_top retained for simulation; earlier no-screen builds are historical evidence only',
        sweep=str(sweep.relative_to(ROOT)),confirmation_matches=True,
        contract='50MHz/48kHz/16bit; R923 valid/R924 cached; lead60; same note events/DAC words; no added pipeline',
        constraints='Original pins/SDC/process unchanged; candidate changes only place/route/clock-order strategy',
        not_verified=['not programmed','no physical audio latency','existing PR1014 and DAC/HDMI external timing/electrical gaps','USB touch not integrated'])
    for label,path in [('hdmi_timing.txt',ROOT/'build/hdmi/timing.txt'),
                       ('sweep_results.csv',sweep/'results.csv')]:
        shutil.copy2(path,OUT/label)
    (OUT/'summary.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS datapath audit: '+str(OUT/'summary.json'))


if __name__=='__main__':main()
