"""Audit current three-effect inputs, then package new builds and preserved room-only references."""
from pathlib import Path
import csv, importlib.util, json, re, sys
from package_room_reverb import ROOT, sha, read, check_manifest, copy as copy_verified, dump, slacks, git

EVIDENCE=ROOT/'verification/evidence/effects'
PACKAGE=ROOT/'build/audition/delay_chorus_j13_20261017'

def copy(source,dest):
    # Gowin marks bitstreams read-only. An identical packaged artifact is already valid.
    if dest.exists():
        if sha(source)==sha(dest):return
        if dest.suffix=='.fs':raise AssertionError('Use a new release directory for a changed bitstream: '+str(dest))
    copy_verified(source,dest)

def model(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'model'/f'{name}.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def main():
    hdmi=ROOT/'build/hdmi';piano=ROOT/'build/effects-noscreen';final=ROOT/'build/regression/final'
    hcheck=json.loads(read(hdmi/'implementation_check.json'))
    assert hcheck['status']=='PASS_CURRENT_CONSTRAINTS_ONLY' and not hcheck['errors']
    for directory in (hdmi,piano):
        check_manifest(directory/'build_inputs.txt')
        body=read(directory/'build.log')
        assert 'Bitstream generation completed' in body
        assert not re.search(r'ERROR|EX3988|EX3791|EX3073|TA2003',body)
    strict_count=check_manifest(ROOT/'build/regression/strict/strict_inputs.txt')
    assert strict_count==171,strict_count
    assert not re.search(r'\*\* (Error|Fatal):',read(ROOT/'build/regression/strict/strict_compile.log'))
    cases=['tb_delay_chorus','tb_room_reverb','tb_effects_pa','tb_effects_hdmi',
           'tb_final_hdmi_isolation','tb_hdmi_octaves','tb_reverb_hdmi_reverb_only',
           'tb_touch_hdmi_audio_dry','tb_hdmi_audio_isolation_legacy']
    tests=[]
    for tag in cases:
        manifest=json.loads(read(final/(tag+'_inputs.json')))
        for path,h in manifest['sha256'].items():
            p=Path(path);p=p if p.is_absolute() else ROOT/p
            assert sha(p)==h,('stale simulation input',tag,path)
        log=read(final/(tag+'_console.log'))
        assert not re.search(r'\bFAIL\b|\*\* (Error|Fatal):',log),tag
        top=tag.removesuffix('_dry').removesuffix('_legacy').removesuffix('_reverb_only')
        lines=[s for s in log.splitlines() if 'PASS '+top in s]
        assert lines,('missing PASS',tag)
        tests.append({'test':tag,'mode':manifest['mode'],'result':lines[-1]})
    baseline=json.loads(read(ROOT/'verification/data/effects_baseline_20261017.json'))
    for path,h in baseline['sha256'].items():assert sha(ROOT/path)==h,('protected file changed',path)
    # Retain and validate the previously delivered room package, including its original docs/evidence.
    previous=ROOT/'build/audition/room_reverb_j13_20261017'
    for folder in (previous,ROOT/'verification/evidence/reverb'):
        for name,record in json.loads(read(folder/'manifest.json'))['files'].items():
            assert sha(folder/name)==record['sha256'],('old delivery changed',folder,name)
    sys.path.insert(0,str(ROOT/'model'))
    model('check_delay_chorus').capture(ROOT/'build/regression/effects/hdmi_audio.csv')
    model('check_room_reverb').check_capture(ROOT/'build/regression/reverb/hdmi_audio.csv')
    tone=model('check_tone_filter');state=0;tone_count=0
    with (final/'touch_audio.csv').open() as stream:
        for row in csv.DictReader(stream):
            state,y=tone.reference(int(row['raw']),int(row['brightness']),state)
            assert y==int(row['filtered']),('dry tone oracle',tone_count)
            tone_count+=1
    assert tone_count>8000 and state==0,tone_count
    vectors=json.loads(read(ROOT/'build/regression/effects/reference.json'))
    assert vectors['vectors_sha256']==sha(ROOT/'build/regression/effects/vectors.txt')
    assert vectors['vectors']==851000
    resources={}
    for name in ['Logic','Register','BSRAM','DSP']:
        m=re.search(r'(?m)^\s*'+name+r'\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',read(piano/'piano_performance.rpt.txt'))
        assert m,name
        resources[name]={'used':float(m[1]),'available':int(m[2])}
    assert resources['BSRAM']['used']==100 and hcheck['resources']['BSRAM']['used']==114
    PACKAGE.mkdir(parents=True,exist_ok=True);EVIDENCE.mkdir(parents=True,exist_ok=True)
    artifacts={}
    files=[
        ('hdmi_delay_chorus_j13.fs',ROOT/'projects/hdmi/impl/pnr/piano_hdmi.fs',hcheck['bitstream_sha256'],'current three-effect build'),
        ('piano_delay_chorus_j13.fs',ROOT/'projects/piano/impl/pnr/piano_performance.fs',None,'current three-effect build'),
        ('hdmi_reverb_only_reference.fs',previous/'hdmi_room_reverb_j13.fs',
         'ba4ee20aca1e0c4299e1ec7bebe8e9fa1511572e78d4b11eb9727e0571e9b42b','preserved prior room-only build'),
        ('piano_reverb_only_reference.fs',previous/'piano_room_reverb_j13.fs',
         'c2aa56b424136860ef2e38e5f94c041c1ab2aa880f0c1bc0e6f252ddf5a0a257','preserved prior room-only build')]
    for name,source,expected,origin in files:
        h=sha(source)
        if expected:assert h==expected,(name,h)
        if name=='piano_delay_chorus_j13.fs':assert re.search(r'(?im)^sha256='+h+r'$',read(piano/'artifact.txt'))
        copy(source,PACKAGE/name)
        artifacts[name]={'bytes':source.stat().st_size,'sha256':h,'origin':origin}
    summary={
        'scope':'fixed shared mono Chorus -> Delay -> Room Reverb, automatic for both instruments',
        'source_base_commit':git('rev-parse','HEAD').decode().strip(),'working_tree_changes':True,
        'programmed':False,'hardware_listening_passed':False,'published':False,
        'sample_rate_hz':48000,'voices':16,'new_controls':False,
        'chorus':{'wet_level_128':24,'ram_words':1024,'ram_word_bits':16,'lfo_phase_steps':[53687,74267],
                  'base_delay_samples':[512,768],'modulation_span_samples':128,'interpolation_fraction_bits':8},
        'delay':{'wet_level_128':16,'samples':7680,'milliseconds':160,'feedback':0.375,'input_weight':0.625,'ram_word_bits':18},
        'reverb':{'wet_level_128':32,'implementation_unchanged':True},
        'extra_clocks_over_room_only':17,'cache_cycles':{'hdmi':953,'no_screen':950},
        'minimum_prepare_cycles':976,'remaining_prepare_cycles':{'hdmi':23,'no_screen':26},
        'strict_verilog_files':strict_count,'protected_existing_files_unchanged':len(baseline['sha256']),
        'protected_baseline_sha256':sha(ROOT/'verification/data/effects_baseline_20261017.json'),
        'tests':tests,'new_unit_vectors':vectors['vectors'],'new_unit_configurations':6,
        'new_unit_vectors_sha256':vectors['vectors_sha256'],'reference_sha256':sha(ROOT/'model/check_delay_chorus.py'),
        'integration_reference':json.loads(read(ROOT/'build/regression/effects/integration_reference.json')),
        'room_compatibility_reference':json.loads(read(ROOT/'build/regression/reverb/integration_reference.json')),
        'dry_tone_reference_samples':tone_count,
        'hdmi':{'resources':hcheck['resources'],'slacks_ns':hcheck['worst_reported_slack_ns'],
                'ports':hcheck['ports'],'constraints':hcheck['active_constraints']},
        'no_screen':{'resources':resources,'slacks_ns':slacks(piano/'timing_from_html.txt'),'ports':25,'constraints':10},
        'artifacts':artifacts,
        'limitations':['PR1014 generic sys clock routing remains','Complete DAC external timing and analog latency unverified',
                       'Actual sound, tail and noise require board/speaker audition','USB touch receiver still absent',
                       'No runtime effects selection; original key and knob functions retained',
                       'Only four HDMI BSRAM blocks remain; no claim of 32 voices or long echo capacity',
                       'No GitHub push or merge performed']}
    for tag in cases:
        for suffix in ['_inputs.json','_compile.log','_console.log']:copy(final/(tag+suffix),EVIDENCE/(tag+suffix))
    for name in ['strict_inputs.txt','strict_compile.log']:copy(ROOT/'build/regression/strict'/name,EVIDENCE/name)
    for name in ['reference.json','integration_reference.json','hdmi_audio.csv']:copy(ROOT/'build/regression/effects'/name,EVIDENCE/name)
    copy(ROOT/'verification/data/effects_baseline_20261017.json',EVIDENCE/'protected_baseline.json')
    for prefix,directory,names in [
        ('hdmi',hdmi,['build_inputs.txt','build.log','timing.txt','implementation_check.json','piano_hdmi.rpt.txt','artifact.txt']),
        ('piano',piano,['build_inputs.txt','build.log','timing_from_html.txt','piano_performance.rpt.txt','artifact.txt'])]:
        for name in names:copy(directory/name,EVIDENCE/(prefix+'_'+name))
    dump(EVIDENCE/'summary.json',summary);dump(PACKAGE/'summary.json',summary)
    copy(ROOT/'docs/delay-chorus.md',PACKAGE/'试听与设计说明.md')
    (PACKAGE/'README.md').write_text('''# 自动轻效果：Delay＋Chorus＋Reverb

接HDMI屏烧录 hdmi_delay_chorus_j13.fs；仅混响对照用 hdmi_reverb_only_reference.fs。
无屏分别使用 piano_delay_chorus_j13.fs / piano_reverb_only_reference.fs。
新版为本轮构建，对照复用上轮已核验文件，具体来源/大小/SHA256见manifest.json和summary.json。

两种乐器均默认自动带效果，无需额外按钮、触摸或上位机设置。
KEY0复位，KEY1中→高→低→中，KEY2钢琴/吉他；双旋钮仍为音量/弯音。
先低音量，试单音、三/四音和弦、快速演奏及两种乐器三个音区。
回声间隔约160ms，轻合唱增加厚度，直达声立即输出。
新版起音比仅混响版约低3dB，比较音色时第二轮可小幅匹配音响响度。
松键等原乐器尾音结束后再等约3秒，不应反复冒出旧音；KEY0应清除旧历史。
详细验收见《试听与设计说明.md》。数字验证/当前约束实现检查通过，尚未替用户烧录或实物验收。
''',encoding='utf-8')
    for folder in (PACKAGE,EVIDENCE):
        dump(folder/'manifest.json',{'files':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)}
             for p in folder.iterdir() if p.is_file() and p.name!='manifest.json'}})
    print('PASS verified three-effect package: '+str(PACKAGE),flush=True)
    print(json.dumps({'tests':len(tests),'strict':strict_count,'protected':len(baseline['sha256']),
                      'hdmi':summary['hdmi'],'no_screen':summary['no_screen']},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
