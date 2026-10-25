"""Collect current brightness evidence; never substitute historical PNR or listening results."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
import argparse

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'build/brightness_response'
OUT=ROOT/'verification/evidence/brightness_response'
BASE='df0e894009e613dbf34011e63bc05653eb92843e'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--functional-only',action='store_true',help='Record only completed functional evidence; no bitstream/timing claim')
parser.add_argument('--baseline',default=BASE,help='Exact preserved baseline commit for this integration')
args=parser.parse_args()
BASE=subprocess.check_output(['git','rev-parse',args.baseline+'^{commit}'],cwd=ROOT,text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return path.read_text(encoding='utf-8-sig')


def verify_inputs(inputs):
    for name,expected in inputs.items():
        path=Path(name)
        if not path.is_absolute():path=ROOT/path
        assert path.is_file() and digest(path)==expected.lower(),('stale input',name)


for action in ('analyze','hdmi'):
    subprocess.run([sys.executable,str(ROOT/'model/brightness_response.py'),action],cwd=ROOT,check=True)
sys.path.insert(0,str(ROOT/'model'))
from check_tone_filter import check_unit
legacy_exact_samples=check_unit()
final=ROOT/'build/regression/final'
cases={}
artifacts={}
for tag in ('tb_brightness_response','tb_brightness_hdmi','tb_tone_filter',
            'tb_controls_meter_hdmi_legacy_brightness'):
    log=final/(tag+'_console.log')
    body=read(log)
    assert not re.search(r'\bFAIL\b|\*\* (Error|Fatal):',body),tag
    lines=[line.removeprefix('# ') for line in body.splitlines() if 'PASS '+tag.removesuffix('_legacy_brightness')+':' in line]
    assert len(lines)==1,tag
    manifest=final/(tag+'_inputs.json')
    data=json.loads(read(manifest))
    verify_inputs(data['sha256'])
    cases[tag]={'result':lines[0],'legacy_brightness':data['legacy_brightness'],
                'functional_rom':data.get('functional_rom',False)}
    for path in (log,manifest):artifacts[path.relative_to(ROOT).as_posix()]=digest(path)
strict=ROOT/'build/regression/strict'
assert 'Errors: 0, Warnings: 0' in read(strict/'strict_compile.log')
strict_inputs={m[2]:m[1] for line in read(strict/'strict_inputs.txt').splitlines()
               if (m:=re.fullmatch(r'([A-Fa-f0-9]{64})  (.+)',line))}
verify_inputs(strict_inputs)
protected_path=WORK/'protected.json'
if not protected_path.exists():
    # Fresh checkouts do not contain another developer's ignored build/ tree.
    # Every generated hash is still checked against the immutable Git baseline below.
    paths=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
    protected={name:digest(ROOT/name) for name in paths if name.startswith(
        ('rtl/synth/','rtl/rom/','verification/tb/','upstream/','boards/')) or name=='projects/hdmi/process_config.json'}
    protected_path.write_text(json.dumps(protected,indent=2)+'\n',encoding='utf-8')
protected=json.loads(read(protected_path))
verify_inputs(protected)
for name in protected:
    original=subprocess.check_output(['git','show',BASE+':'+name],cwd=ROOT)
    assert original.replace(b'\r\n',b'\n')==(ROOT/name).read_bytes().replace(b'\r\n',b'\n'),name

OUT.mkdir(parents=True,exist_ok=True)
if args.functional_only:
    result={'status':'PASS_FUNCTIONAL_ONLY','base_commit':BASE,
            'legacy_exact_samples':legacy_exact_samples,
            'strict_verilog_files':len(strict_inputs),'preserved_original_files':len(protected),
            'tests':cases,'response':json.loads(read(WORK/'response.json')),
            'integration':json.loads(read(WORK/'hdmi_reference.json')),
            'source_sha256':{str(Path(n).relative_to(ROOT)):h for n,h in strict_inputs.items()},
            'model_sha256':digest(ROOT/'model/brightness_response.py'),
            'implementation_verified':False,'hardware_listening_verified':False,
            'limits':['This functional snapshot does not certify a bitstream or physical timing.']}
    (OUT/'functional_summary.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('PASS functional evidence only; implementation and hardware listening not certified')
    sys.exit(0)

implementation=json.loads(read(ROOT/'build/hdmi/implementation_check.json'))
verify_inputs({item['path']:item['sha256'] for item in implementation['inputs']})
assert implementation['status']=='PASS_CURRENT_CONSTRAINTS_ONLY',implementation['errors']
fs=ROOT/'projects/hdmi/impl/pnr/piano_hdmi.fs'
assert digest(fs)==implementation['bitstream_sha256']
for path in (strict/'strict_inputs.txt',strict/'strict_compile.log',WORK/'protected.json',
             WORK/'vectors.txt',WORK/'actual.csv',WORK/'response.json',WORK/'hdmi.csv',WORK/'hdmi_reference.json',
             ROOT/'model/brightness_response.py',ROOT/'model/check_delay_chorus.py',ROOT/'model/check_room_reverb.py',
             ROOT/'model/check_tone_filter.py',ROOT/'build/expression/tone_vectors.txt',
             ROOT/'build/expression/tone_actual.csv',ROOT/'build/hdmi/implementation_check.json',Path(__file__)):
    artifacts[path.relative_to(ROOT).as_posix()]=digest(path)
result={'status':'PASS_OFFLINE_CURRENT_CONSTRAINTS_ONLY','base_commit':BASE,
        'legacy_exact_samples':legacy_exact_samples,
        'strict_verilog_files':len(strict_inputs),'preserved_original_files':len(protected),
        'tests':cases,'response':json.loads(read(WORK/'response.json')),
        'integration':json.loads(read(WORK/'hdmi_reference.json')),
        'audio_contract':{'voices':32,'sample_rate_hz':48000,'cache_cycle':958,'prepare_cycles':976,'spare_cycles':18},
        'resources':implementation['resources'],'worst_reported_slack_ns':implementation['worst_reported_slack_ns'],
        'ports':implementation['ports'],'active_constraints':implementation['active_constraints'],
        'bitstream':fs.relative_to(ROOT).as_posix(),'bitstream_sha256':digest(fs),
        'source_inputs':implementation['inputs'],'artifacts':artifacts,
        'limitations':implementation['limitations']+['Brightness hardware listening has not been tested.',
             'No claim of reproducing the reported hardware symptom; the change improves verified digital response.',
             'Offline evidence does not certify hardware programming or physical listening.']}
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS brightness evidence:',len(cases),'tests;',len(protected),'preserved files; current PNR checked')
