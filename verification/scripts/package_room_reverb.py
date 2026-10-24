"""Package only matching, verified local reverb builds; never programs or publishes."""
from pathlib import Path
import hashlib, importlib.util, json, re, shutil, subprocess

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'verification/evidence/reverb'
PACKAGE=ROOT/'build/audition/room_reverb_j13_20261017'

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):return Path(path).read_text(encoding='utf-8-sig')
def check_manifest(path):
    text=read(path);items=re.findall(r'(?m)^([a-fA-F0-9]{64})  (.+)$',text)
    assert len(items)>30, ('incomplete manifest',path)
    for h,p in items:assert sha(p.strip())==h.lower(), ('stale build/compile input',p)
    return len(items)
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def copy(source,dest):
    dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,dest)
    assert sha(source)==sha(dest)
def dump(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def slacks(path):
    text=read(path);out={}
    for title in ['3.1.1 Setup Paths Table','3.1.2 Hold Paths Table','3.1.3 Recovery Paths Table',
                  '3.1.4 Removal Paths Table','3.2 Minimum Pulse Width Table']:
        table=text.split(title,1)[1].strip().split('\n\n',1)[0]
        values=[float(x) for x in re.findall(r'(?m)^\s*\d+\s+(-?\d+\.\d+)\s+',table)]
        assert values and min(values)>=0,(title,values)
        out[title]=min(values)
    return out

def main():
    hdmi=ROOT/'build/hdmi';piano=ROOT/'build/reverb-noscreen';final=ROOT/'build/regression/final'
    hcheck=json.loads(read(hdmi/'implementation_check.json'))
    assert hcheck['status']=='PASS_CURRENT_CONSTRAINTS_ONLY' and not hcheck['errors']
    for directory in [hdmi,piano]:
        check_manifest(directory/'build_inputs.txt')
        log=read(directory/'build.log')
        assert 'Bitstream generation completed' in log
        assert not re.search(r'ERROR|EX3988|EX3791|EX3073|TA2003',log)
    strict_count=check_manifest(ROOT/'build/regression/strict/strict_inputs.txt')
    assert strict_count==166,strict_count
    assert not re.search(r'\*\* (Error|Fatal):',read(ROOT/'build/regression/strict/strict_compile.log'))
    cases=['tb_room_reverb','tb_reverb_pa','tb_reverb_hdmi','tb_final_hdmi_isolation','tb_hdmi_octaves',
           'tb_touch_hdmi_audio_dry','tb_hdmi_audio_isolation_legacy']
    tests=[]
    for tag in cases:
        manifest=json.loads(read(final/(tag+'_inputs.json')))
        for path,h in manifest['sha256'].items():
            p=Path(path);p=p if p.is_absolute() else ROOT/p
            assert sha(p)==h,('stale simulation',tag,path)
        log=read(final/(tag+'_console.log'))
        assert not re.search(r'\bFAIL\b|\*\* (Error|Fatal):',log),tag
        lines=[s for s in log.splitlines() if 'PASS '+tag.removesuffix('_dry').removesuffix('_legacy') in s]
        assert lines,('missing PASS',tag)
        tests.append({'test':tag,'mode':manifest['mode'],'result':lines[-1]})
    # Existing files in these areas are protected; new independent test modules are allowed.
    protected=['rtl/synth','rtl/rom','rtl/control','rtl/display','rtl/audio','verification/tb','upstream','boards','host',
               'projects/hdmi/process_config.json','projects/piano/process_config.json']
    assert not git('diff','--name-only','HEAD','--',*protected).strip(),'Protected existing input changed'
    paths=git('ls-tree','-r','--name-only','HEAD','--',*protected).decode('utf-8').splitlines()
    spec=importlib.util.spec_from_file_location('room_reference',ROOT/'model/check_room_reverb.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.check_capture(ROOT/'build/regression/reverb/hdmi_audio.csv')
    tone_spec=importlib.util.spec_from_file_location('tone_reference',ROOT/'model/check_tone_filter.py')
    tone=importlib.util.module_from_spec(tone_spec);tone_spec.loader.exec_module(tone)
    import csv
    state=0;tone_count=0
    with (final/'touch_audio.csv').open() as f:
        for row in csv.DictReader(f):
            state,y=tone.reference(int(row['raw']),int(row['brightness']),state)
            assert y==int(row['filtered']),('dry tone oracle',tone_count)
            tone_count+=1
    assert tone_count>8000 and state==0,tone_count
    PACKAGE.mkdir(parents=True,exist_ok=True);EVIDENCE.mkdir(parents=True,exist_ok=True)
    artifacts={}
    files=[
        ('hdmi_room_reverb_j13.fs','projects/hdmi/impl/pnr/piano_hdmi.fs',None,'new wet build'),
        ('piano_room_reverb_j13.fs','projects/piano/impl/pnr/piano_performance.fs',None,'new wet build'),
        ('hdmi_dry_reference.fs','build/audition/touch_brightness_prepare_20261017/hdmi_touch_brightness_preview.fs',
         '93eae4d1294394a11e1ca9f599ff4ff9b9850b2f3941b47848078748d3614658','c250399 prior verified dry build'),
        ('piano_dry_reference.fs','build/audition/octave3_j13_20261017/piano_octave3_j13.fs',
         '4ccb941929d959f77738d0e97798cc505d3499dd6a04b962be905083fa0f03c9','a0684e4 prior verified dry build')]
    for name,source,expected,origin in files:
        source=ROOT/source;h=sha(source)
        if expected:assert h==expected
        if name.startswith('hdmi_room'):assert h==hcheck['bitstream_sha256']
        if name.startswith('piano_room'):
            assert re.search(r'(?im)^sha256='+h+r'$',read(piano/'artifact.txt'))
        copy(source,PACKAGE/name)
        artifacts[name]={'sha256':h,'bytes':source.stat().st_size,'origin':origin}
    resources={}
    for name in ['Logic','Register','BSRAM','DSP']:
        m=re.search(r'(?m)^\s*'+name+r'\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',read(piano/'piano_performance.rpt.txt'))
        assert m,name
        resources[name]={'used':float(m[1]),'available':int(m[2])}
    assert resources['BSRAM']['used']==90 and hcheck['resources']['BSRAM']['used']==104
    summary={'scope':'default mono room reverb for both instruments; no delay/chorus/USB touch driver',
        'source_base_commit':git('rev-parse','HEAD').decode().strip(),'working_tree_changes':True,
        'programmed':False,'hardware_listening_passed':False,'published':False,
        'sample_rate_hz':48000,'voices':16,'wet_level_128':32,
        'extra_pipeline_clocks':9,'cache_cycles':{'hdmi':936,'no_screen':933},'minimum_prepare_cycles':976,
        'strict_verilog_files':strict_count,'protected_existing_files_unchanged':len(paths),
        'tests':tests,'unit_vectors':json.loads(read(ROOT/'build/regression/reverb/reference.json'))['vectors'],
        'unit_vectors_sha256':sha(ROOT/'build/regression/reverb/vectors.txt'),
        'room_reference_sha256':sha(ROOT/'model/check_room_reverb.py'),
        'integration_reference':json.loads(read(ROOT/'build/regression/reverb/integration_reference.json')),
        'dry_tone_reference_samples':tone_count,
        'hdmi':{'resources':hcheck['resources'],'slacks_ns':hcheck['worst_reported_slack_ns'],
                'ports':hcheck['ports'],'constraints':hcheck['active_constraints']},
        'no_screen':{'resources':resources,'slacks_ns':slacks(piano/'timing_from_html.txt'),'ports':25,'constraints':10},
        'artifacts':artifacts,
        'limitations':['PR1014 generic sys clock routing remains','Complete DAC external timing and analog latency unverified',
                       'Actual room sound and silence require board/speaker audition','Physical USB touch receiver still absent',
                       'No new GitHub push or merge performed']}
    for tag in cases:
        for suffix in ['_inputs.json','_compile.log','_console.log']:
            copy(final/(tag+suffix),EVIDENCE/(tag+suffix))
    for name in ['strict_inputs.txt','strict_compile.log']:
        copy(ROOT/'build/regression/strict'/name,EVIDENCE/name)
    for name in ['reference.json','integration_reference.json','hdmi_audio.csv']:
        copy(ROOT/'build/regression/reverb'/name,EVIDENCE/name)
    for prefix,directory,names in [
        ('hdmi',hdmi,['build_inputs.txt','build.log','timing.txt','implementation_check.json','piano_hdmi.rpt.txt','artifact.txt']),
        ('piano',piano,['build_inputs.txt','build.log','timing_from_html.txt','piano_performance.rpt.txt','artifact.txt'])]:
        for name in names:copy(directory/name,EVIDENCE/(prefix+'_'+name))
    dump(EVIDENCE/'summary.json',summary);dump(PACKAGE/'summary.json',summary)
    copy(ROOT/'docs/reverb.md',PACKAGE/'试听与设计说明.md')
    (PACKAGE/'README.md').write_text('''# 默认轻混响试听包

接HDMI屏请烧录 **hdmi_room_reverb_j13.fs**；对照干声用 **hdmi_dry_reference.fs**。
无屏工程分别用 piano_room_reverb_j13.fs / piano_dry_reference.fs。
干声来自上轮已验证基准，混响是本轮新构建，来源和SHA256见manifest.json/summary.json。

KEY0复位；KEY1中→高→低音区；KEY2钢琴/吉他。双旋钮仍为音量/弯音。
混响默认开启，不用另找开关；明亮度滑条保留，USB触摸接收尚未接通。

先低音量，弹单音、三/四音和弦，对照尾响是否自然、起音是否清楚，检查三音区和两个乐器。
所有键松开3秒后应没有残留乐音；连续演奏不应卡音、周期性爆音或异常改调。
详细步骤见同目录《试听与设计说明.md》。模拟/实现检查已通过，实物听感尚待你们确认。
''',encoding='utf-8')
    dump(PACKAGE/'manifest.json',{'files':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)}
         for p in PACKAGE.iterdir() if p.is_file() and p.name!='manifest.json'}})
    dump(EVIDENCE/'manifest.json',{'files':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)}
         for p in EVIDENCE.iterdir() if p.is_file() and p.name!='manifest.json'}})
    print('PASS verified package: '+str(PACKAGE),flush=True)
    print(json.dumps({'tests':len(tests),'strict':strict_count,'protected':len(paths),'hdmi':summary['hdmi'],'no_screen':summary['no_screen']},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
