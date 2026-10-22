"""Check current touch preparation evidence; no physical USB/hardware claims.

Run after the documented simulations and, for --package, the current HDMI build.
"""
from pathlib import Path
import argparse, csv, hashlib, importlib.util, json, re, shutil, subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/regression/final'
EVIDENCE=ROOT/'verification/evidence/touch'
BASE='a0684e4b7c19ec895eee61adf9bcf95b148ce355'
p=argparse.ArgumentParser()
p.add_argument('--package',action='store_true',help='Also verify current disconnected-preview PNR and package its bitstream')
a=p.parse_args()
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def read(path):return path.read_text(encoding='utf-8-sig')
def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

cases=['tb_touch_brightness','tb_touch_hdmi_audio','tb_touch_display','tb_tone_filter',
       'tb_brightness_keys','tb_panel_octaves','tb_final_hdmi_isolation','tb_hdmi_octaves','tb_final_display_ui']
evidence_files=[]
passes={}
for name in cases:
    log=OUT/(name+'_console.log')
    body=read(log)
    assert not re.search(r'\bFAIL\b|\*\* (Error|Fatal):',body),name
    lines=[s.removeprefix('# ') for s in body.splitlines() if 'PASS '+name+':' in s]
    assert len(lines)==1,name
    passes[name]=lines[0]
    manifest=OUT/(name+'_inputs.json')
    for filename,value in json.loads(read(manifest))['sha256'].items():
        f=Path(filename)
        if not f.is_absolute():f=ROOT/f
        assert sha(f)==value,(name,'input changed',filename)
    evidence_files.extend([log,manifest])

strict=ROOT/'build/regression/strict'
strict_body=read(strict/'strict_compile.log')
assert re.search(r'Errors: 0, Warnings: 0',strict_body),'strict compile failed'
strict_count=0
for line in read(strict/'strict_inputs.txt').splitlines():
    m=re.fullmatch(r'([A-Fa-f0-9]{64})  (.+)',line)
    if m:
        assert sha(Path(m[2]))==m[1].lower(),('strict input changed',m[2])
        strict_count+=1
assert strict_count>=162,strict_count
evidence_files.extend([strict/'strict_compile.log',strict/'strict_inputs.txt'])

spec=importlib.util.spec_from_file_location('tone_reference',ROOT/'model/check_tone_filter.py')
oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
unit=oracle.check_unit()
rows=list(csv.DictReader((OUT/'touch_audio.csv').open()))
state=0;changed=0;bypass=0;full=0
for i,row in enumerate(rows):
    x,t,actual=(int(row[k]) for k in ('raw','brightness','filtered'))
    state,expected=oracle.reference(x,t,state)
    assert expected==actual,('independent touch oracle',i,x,t,expected,actual)
    if t==127:
        assert x==actual
        bypass+=1
    elif actual!=x:changed+=1
    if int(row['voices'])==16:full+=1
assert state==0 and changed>500 and bypass>100 and full>500,(state,changed,bypass,full)

# Check preservation against the exact published octave commit, not stale local copies.
protected=git('ls-tree','-r','--name-only',BASE,'rtl/synth','rtl/rom','rtl/audio','boards','upstream',
              'verification/tb','projects/hdmi/process_config.json','projects/piano',
              'rtl/control/piano_controls.v','rtl/control/ads1115_knob_if.v').decode().splitlines()
changed_names=set(git('diff','--name-only',BASE,'--',*protected).decode().splitlines())
assert not changed_names,('protected files changed',sorted(changed_names))
font_before=git('show',BASE+':rtl/display/display_font_ui.v').decode('utf-8')
font_now=read(ROOT/'rtl/display/display_font_ui.v')
def preserved_font(s):
    result=[]
    for l in s.splitlines():
        m=re.search(r'(text|title)_rom\[(\d+)\] =',l)
        if m and (m[1]=='title' or int(m[2])<58*32):result.append(l.strip())
    return result
assert preserved_font(font_before)==preserved_font(font_now),'published glyph changed'

EVIDENCE.mkdir(parents=True,exist_ok=True)
for src in evidence_files:shutil.copyfile(src,EVIDENCE/src.name)
for name in ['touch_disconnected','touch_dark','touch_guitar_mid']:
    frame=OUT/(name+'.hex')
    subprocess.run([__import__('sys').executable,str(ROOT/'verification/scripts/render_display_frame.py'),
                    str(frame),str(EVIDENCE/(name+'.png')),'--width','1024','--height','600'],check=True,cwd=ROOT)

summary={'baseline_commit':BASE,'scope':'FPGA normalized-coordinate control and display preparation',
         'physical_usb_input_implemented':False,'hardware_verified':False,'strict_verilog_files':strict_count,
         'tests':passes,'unit_filter_reference_samples':unit,'touch_filter_reference_samples':len(rows),
         'exact_bypass_samples':bypass,'changed_tone_samples':changed,'full_16_voice_samples':full,
         'protected_published_files_unchanged':len(protected),'old_font_rows_unchanged':True,
         'current_usb_boundary':'Tied disconnected; testbench reports are simulation only',
         'audio_contract':'HDMI R927, no-screen R924; default127 exact original samples',
         'touch_csv_sha256':sha(OUT/'touch_audio.csv'),
         'checker_sha256':sha(Path(__file__))}
if a.package:
    implementation=json.loads(read(ROOT/'build/hdmi/implementation_check.json'))
    assert implementation['status']=='PASS_CURRENT_CONSTRAINTS_ONLY',implementation['errors']
    for item in implementation['inputs']:assert sha(Path(item['path']))==item['sha256'],item['path']
    fs=ROOT/'projects/hdmi/impl/pnr/piano_hdmi.fs'
    assert sha(fs)==implementation['bitstream_sha256']
    for name in ['implementation_check.json','build_inputs.txt','timing.txt']:
        shutil.copyfile(ROOT/'build/hdmi'/name,EVIDENCE/('preview_'+name))
    summary['disconnected_preview_build']={k:implementation[k] for k in
        ['status','resources','worst_reported_slack_ns','ports','active_constraints','bitstream_sha256']}
    summary['disconnected_preview_build']['limitation']='Constant disconnected input is optimized; dynamic host/control path must be implemented and rebuilt later'
    package=ROOT/'build/audition/touch_brightness_prepare_20261017'
    package.mkdir(parents=True,exist_ok=True)
    dest=package/'hdmi_touch_brightness_preview.fs'
    shutil.copyfile(fs,dest)
    assert sha(dest)==sha(fs)
    (package/'README.md').write_text('''# HDMI触摸明亮度控件预览（尚无物理触摸）

本包适用于当前Tang Mega60K＋NEO Dock31005／J13接线，使用SRAM Program可查看新增控件。
KEY0复位；KEY1中→高→低音区；KEY2钢琴／经典摇滚；实体13键、双旋钮和UART保留。

屏幕上方显示“明亮度127 / 触摸关”，手指现在不会起作用，因为USB主机与触摸数据线尚未接通。
默认127保持原始数字样本；不要把本包当作USB触摸完成版，不用电脑转发代替最终独立运行。
当前R927音频缓存；旧音区包保留。实屏与真实听感需用户低音量检查，本次没有代为下载。

预览核对：标题／滑条／原音按钮无重叠；KEY1仍换三音区，KEY2仍换两乐器；13键和弦、双旋钮及松键收尾正常。
只有HDMI连接时应显示“触摸关”；USB链路接入后另行发布可交互版本。
完整交接见仓库docs/touch-brightness.md；验证与原约束时序见本目录summary.json和implementation_check.json。
''',encoding='utf-8')
    shutil.copyfile(ROOT/'build/hdmi/implementation_check.json',package/'implementation_check.json')
    summary['preview_package']=dest.relative_to(ROOT).as_posix()
    save(package/'summary.json',summary)
    save(package/'manifest.json',{'files':{x.name:{'bytes':x.stat().st_size,'sha256':sha(x)}
        for x in package.iterdir() if x.is_file() and x.name!='manifest.json'}})
summary['evidence_sha256']={f.name:sha(f) for f in EVIDENCE.iterdir() if f.is_file() and f.name!='summary.json'}
save(EVIDENCE/'summary.json',summary)
print(f'PASS touch preparation: {len(cases)} tests, {unit} unit + {len(rows)} integrated exact samples; physical USB still pending')
