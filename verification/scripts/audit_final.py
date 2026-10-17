"""Audit current integration evidence against real files; never infer hardware acceptance."""
from pathlib import Path
import hashlib,json,re,subprocess
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/integration/20261016'
FINAL=ROOT/'build/regression/final'
reviewed_inputs={}
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def require(condition,message):
    if not condition:raise SystemExit('FAIL final audit: '+message)
def matching_inputs(path):
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    for name,digest in data['sha256'].items():
        file=ROOT/name
        require(file.is_file() and sha(file)==digest,'stale test dependency '+str(file))
        if file.is_relative_to(ROOT):
            relative=file.relative_to(ROOT).as_posix()
            if not relative.startswith('build/'):reviewed_inputs[relative]=digest
    return {'manifest':str(path.relative_to(ROOT)),'sha256':sha(path),'dependencies':len(data['sha256'])}
def manifest_txt(path):
    count=0
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        match=re.fullmatch(r'([a-fA-F0-9]{64})  (.+)',line)
        if match:
            file=Path(match[2]);count+=1
            require(file.exists() and sha(file)==match[1].lower(),'stale build dependency '+str(file))
            if file.is_relative_to(ROOT):
                relative=file.relative_to(ROOT).as_posix()
                if not relative.startswith('build/'):reviewed_inputs[relative]=match[1].lower()
    require(count>20,'incomplete manifest '+str(path))
    return {'sha256':sha(path),'dependencies':count}
current=['tb_final_modal_adapter','tb_final_performance','tb_performance_latency',
         'tb_final_wave_envelope','tb_final_display_frame','tb_final_display_ui',
         'tb_final_hdmi_isolation','tb_final_env_alignment']
tests={}
for top in current:
    log=FINAL/(top+'.log');body=log.read_text(errors='replace')
    require('PASS '+top in body and not re.search(r'\bFAIL\b|\*\* (Error|Fatal):',body),'failed/missing '+top)
    tests[top]={**matching_inputs(FINAL/(top+'_inputs.json')),'log_sha256':sha(log),
                'pass':[s for s in body.splitlines() if 'PASS '+top in s]}
music={}
for top in ['tb_music_protocol','tb_music_pipe','tb_music_uart16','tb_music_display_isolation',
            'tb_music_controls','tb_music_local_controls','tb_music_recovery']:
    folder=ROOT/'build/regression/music';log=folder/(top+'.log');body=log.read_text(errors='replace')
    require('PASS '+top in body and not re.search(r'\bFAIL\b|\*\* (Error|Fatal):',body),'failed A regression '+top)
    music[top]={**matching_inputs(folder/(top+'_inputs.json')),'log_sha256':sha(log)}
baseline=json.loads((ROOT/'verification/data/protected_inputs.json').read_text(encoding='utf-8-sig'))
protected=[]
for record in baseline:
    name=record['path'];file=ROOT/name
    if name.startswith(('verification/tb/','upstream/')) or name.endswith('.sdc') or \
       Path(name).name in ('process_config.json','hdmi_reset_placement.cst','hdmi.cst') or \
       name in ('rtl/display/dvi_tx_gowin.v','rtl/display/hdmi_clock_60k.v','rtl/display/hdmi_reset_guard.v','rtl/display/tmds_encoder.v','verification/data/display_font_golden.mem'):
        require(file.exists() and sha(file)==record['sha256'].lower(),'protected input changed '+name)
        protected.append(record)
imports=json.loads((ROOT/'verification/data/upstream_imports.json').read_text(encoding='utf-8-sig'))
for record in imports:require(sha(ROOT/record['path'])==record['sha256'].lower(),'upstream original changed '+record['path'])
strict=manifest_txt(ROOT/'build/regression/strict/strict_inputs.txt')
hdmi=json.loads((ROOT/'build/hdmi/implementation_check.json').read_text())
require(hdmi['status']=='PASS_CURRENT_CONSTRAINTS_ONLY' and not hdmi['errors'],'HDMI implementation gate')
for item in hdmi['inputs']:
    require(sha(item['path'])==item['sha256'],'HDMI report is stale: '+item['path'])
builds={}
for name,folder,base in [('hdmi',ROOT/'build/hdmi',ROOT/'projects/hdmi/impl/pnr/piano_hdmi'),
                         ('noscreen',ROOT/'build/final-noscreen',ROOT/'projects/piano/impl/pnr/piano_performance')]:
    timing=(folder/('timing.txt' if name=='hdmi' else 'timing_from_html.txt')).read_text(encoding='utf-8-sig')
    slacks={}
    for section in ('3.1.1 Setup Paths Table','3.1.2 Hold Paths Table','3.1.3 Recovery Paths Table','3.1.4 Removal Paths Table','3.2 Minimum Pulse Width Table'):
        require(section in timing,'missing '+section)
        table=timing.split(section,1)[1].strip().split('\n\n',1)[0]
        values=[float(x) for x in re.findall(r'(?m)^\s*\d+\s+(-?\d+\.\d+)\s+',table)]
        require(values and min(values)>=0,'timing violation '+name+' '+section);slacks[section]=min(values)
    report=base.with_suffix('.rpt.txt').read_text(encoding='utf-8-sig')
    resources={}
    for label in (('Logic','Register','BSRAM','DSP','PLLA') if name=='hdmi' else ('Logic','Register','BSRAM','DSP')):
        match=re.search(rf'(?m)^\s*{label}\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',report)
        require(match is not None,'missing resource '+label)
        used=float(match[1]);resources[label]={'used':int(used) if used.is_integer() else used,'available':int(match[2])}
    builds[name]={'manifest':manifest_txt(folder/'build_inputs.txt'),'slack_ns':slacks,'resources':resources,
        'bitstream':str(base.with_suffix('.fs').relative_to(ROOT)),'bitstream_sha256':sha(base.with_suffix('.fs')),
        'report_sha256':sha(base.with_suffix('.rpt.txt'))}
for mutation,top,marker in [('Preset','tb_final_modal_adapter','FAIL modal golden mismatch'),
    ('Release','tb_final_modal_adapter','FAIL stale release'),('Wave','tb_final_wave_envelope','FAIL pair peak lost'),
    ('Env','tb_final_env_alignment','FAIL env current preset')]:
    tag=top+'_'+mutation;body=(FINAL/(tag+'.log')).read_text(errors='replace')
    require(marker in body and 'PASS '+top not in body,'mutation survived '+mutation)
    matching_inputs(FINAL/(tag+'_inputs.json'))
latency=(FINAL/'tb_performance_latency.log').read_text()
maximum=int(re.search(r'maximum_observed_ns=(\d+)',latency)[1])
require(maximum<=2200000,'digital onset boundary failed')
previews={}
for mode in ('piano','guitar'):
    # UI=0兼容帧和UI=1正式帧必须分别保留，禁止拷贝覆盖转储来迎合检查。
    png=ROOT/('docs/display-'+mode+'.png');raw=FINAL/(mode+'_ui_frame.hex')
    with Image.open(png) as frame:
        require(frame.size==(1024,600) and frame.mode=='RGB','invalid preview format '+mode)
        require(frame.tobytes()==bytes.fromhex(''.join(raw.read_text().splitlines())),'preview not generated from current UI=1 RTL pixels '+mode)
    require(sha(raw)!=sha(FINAL/(mode+'_frame.hex')),'formal/compatibility frame identities unexpectedly equal '+mode)
    previews[mode]={'image_sha256':sha(png),'raw_rgb_sha256':sha(raw),'width':1024,'height':600,
        'producer':'tb_final_display_ui','ui':1,'raw':str(raw.relative_to(ROOT))}
pins_path=OUT/'pins_final.json';pins=json.loads(pins_path.read_text(encoding='utf-8-sig'))
require(pins['status']=='PASS_PIN_CONTRACT_ONLY' and len(pins.get('negative_controls',[]))==3,'pin verification incomplete')
require(pins['cst_sha256']==sha(ROOT/'boards/tang_mega_60k_31004/piano.cst'),'pin check stale')
for path,digest in pins['reports'].items():require(sha(ROOT/path)==digest,'pin report stale')
auxiliary={}
for name,path,marker in [('host53','host_tests.log','Ran 53 tests'),('dual_host4','dual_host_tests.log','Ran 4 tests')]:
    file=OUT/path;body=file.read_text(encoding='utf-8-sig',errors='replace')
    require(marker in body and re.search(r'(?m)^OK\s*$',body) is not None,'host verification failed '+name)
    auxiliary[name]={'log_sha256':sha(file),'hardware_opened':False}
summary={'date':'2026-10-17','status':'LOCAL_IMPLEMENTATION_VERIFIED_HARDWARE_PENDING',
    'upstream_commit':'e18160e4ae1f7023447819e780669055c869788a','strict':strict,
    'current_tests':tests,'original_A_tests':music,'imports_unchanged':len(imports),
    'protected_inputs_unchanged':len(protected),'builds':builds,
    'source_sha256':dict(sorted(reviewed_inputs.items())),
    'negative_controls':['Preset','Release','Wave','Env'],'pins':pins,'previews':previews,'host':auxiliary,
    'digital_latency_max_observed_ns':maximum,
    'digital_latency_scope':'13 default production key onsets to complete nonzero left DAC word; excludes mechanical bounce and analog output',
    'programmed':False,'connector_orientation_evidence':'User front N/1 and 2/P marks plus mirrored rear square pad: front Ethernet left/PCIe below, pin1 upper right, pin2 lower right',
    'hardware_acceptance_pending':['eight white/five black keys and K6','new piano/guitar listening','new screen firmware','knob noise/center calibration','analog end-to-end latency'],
    'external_timing_pending':['PR1014','complete DAC setup/hold budget','SDA output-enable coverage','HDMI board/cable electrical budget']}
dest=ROOT/'verification/evidence/final/summary.json';dest.parent.mkdir(parents=True,exist_ok=True)
dest.write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(OUT/'protected_inputs.json').write_text(json.dumps(protected,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS final audit: '+str(len(tests))+' current + '+str(len(music))+' original A tests; '+str(len(protected))+' protected inputs; both implemented images. Hardware remains pending.')
