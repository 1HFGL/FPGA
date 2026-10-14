"""Record source changes, exact pin placement and completed checks for review."""
from pathlib import Path
import difflib
import hashlib
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/keyboard-verification'
baseline_path=ROOT/'source_baseline.json'
if not baseline_path.is_file(): baseline_path=ROOT/'verification/source_baseline.json'
baseline=json.loads(baseline_path.read_text(encoding='utf-8'))
snapshot=ROOT.parent/'github_review_20261014/branches/master'

def original_data(name):
    if snapshot.is_dir():
        original=snapshot/name
        return original.read_bytes() if original.is_file() else b''
    # A normal Git checkout can recover the baseline without any external cache.
    original=subprocess.run(['git','show',baseline['commit']+':'+name],cwd=ROOT,capture_output=True)
    if original.returncode:
        if name not in {entry['path'] for entry in baseline['files']}: return b''
        raise RuntimeError('Cannot read Git baseline file: '+name)
    return original.stdout

def git_hash(data):
    return hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()

preserved_tests=0
changes=[]
diffs=[]
paths={e['path']:e['git_blob'] for e in baseline['files']}
for folder in ['rtl','boards','projects','verification','docs']:
    for file in (ROOT/folder).rglob('*'):
        if file.is_file() and 'impl' not in file.parts:
            paths.setdefault(file.relative_to(ROOT).as_posix(),None)
for name in sorted(paths):
    if name=='source_baseline.json': continue
    path=ROOT/name
    old_data=original_data(name)
    new_data=path.read_bytes() if path.is_file() else b''
    if name.startswith(('verification/tb/','upstream/fpga_interaction/tb/')) and paths[name]:
        assert git_hash(new_data)==paths[name], 'Original teammate test changed: '+name
        preserved_tests+=1
    if old_data==new_data: continue
    changes.append({'path':name,'status':'added' if paths[name] is None else 'modified',
                    'sha256':hashlib.sha256(new_data).hexdigest()})
    old_lines=[line+'\n' for line in old_data.decode('utf-8').splitlines()]
    new_lines=[line+'\n' for line in new_data.decode('utf-8').splitlines()]
    diffs.extend(difflib.unified_diff(old_lines,new_lines,fromfile='a/'+name if paths[name] else '/dev/null',
        tofile='b/'+name))
(OUT/'source_changes.diff').write_text(''.join(diffs),encoding='utf-8')

tests={}
for group,expected in [('control',7),('piano',2),('uart',7)]:
    body=(OUT/(group+'.log')).read_text(encoding='utf-8-sig')
    names=re.findall(r'^VERIFIED (\w+)\s*$',body,re.M)
    assert len(names)==expected and not re.search(r'\*\* (Fatal|Error):|\bFAIL\b',body), group
    tests[group]=names
tests['keyboard']=[]
for name in ['tb_piano_13_keys','tb_piano_13_debounce']:
    body=(ROOT/'build/regression/keyboard'/f'{name}.log').read_text(encoding='utf-8-sig')
    assert f'PASS {name}:' in body and not re.search(r'\*\* (Fatal|Error):|\bFAIL\b',body),name
    tests['keyboard'].append(name)
strict=(ROOT/'build/regression/strict/strict_inputs.txt').read_text(encoding='utf-8-sig')
compiled=len(re.findall(r'^[0-9A-F]{64} ',strict,re.M))
assert compiled==87
compile_log=(ROOT/'build/regression/strict/strict_compile.log').read_text(encoding='utf-8-sig')
assert 'Errors: 0' in compile_log

timing=(ROOT/'build/piano/timing_from_html.txt').read_text(encoding='utf-8')
slacks={}
for title,key in [('3.1.1 Setup Paths Table','setup'),('3.1.2 Hold Paths Table','hold'),
                  ('3.1.3 Recovery Paths Table','recovery'),('3.1.4 Removal Paths Table','removal'),
                  ('3.2 Minimum Pulse Width Table','pulse_width')]:
    section=timing.split(title,1)[1].lstrip('\n').split('\n\n',1)[0]
    values=[float(v) for v in re.findall(r'^\d+\s+(-?\d+\.\d+)',section,re.M)]
    assert values and min(values)>=0,key
    slacks[key]=min(values)
assert re.search(r'sys_clk Setup 0\.000 0',timing)
assert re.search(r'sys_clk Hold 0\.000 0',timing)
rpt=(ROOT/'projects/piano/impl/pnr/piano_13key.rpt.txt').read_text(encoding='utf-8')
cst=(ROOT/'boards/tang_mega_60k_31004/piano.cst').read_text(encoding='utf-8')
locations=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',cst))
assert len(locations)==23 and len(set(locations.values()))==23
original_locations=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',original_data('boards/tang_mega_60k_31004/piano.cst').decode('utf-8')))
assert all(locations[k]==v for k,v in original_locations.items())
for name,ball in locations.items():
    line=re.search(r'^'+re.escape(name)+r'\s*\|[^\n]+',rpt,re.M)[0]
    fields=[x.strip() for x in line.split('|')]
    assert fields[2].split('/')[0]==ball and fields[3]=='Y',name
    if name.startswith('piano_key_n'):
        assert fields[4]=='in' and 'LVCMOS33' in fields and 'UP' in fields and '3.3' in fields,name
config=(ROOT/'projects/piano/process_config.json').read_bytes()
effective=(ROOT/'projects/piano/impl/uart_piano_process_config.json').read_bytes()
assert config==effective and json.loads(config)['CPU'] is True
fs=ROOT/'projects/piano/impl/pnr/piano_13key.fs'
assert fs.is_file()
resources={k:float(re.search(r'\b'+k+r'\s*\|\s*(\d+(?:\.\d+)?)/',rpt)[1])
           for k in ['Logic','Register','BSRAM','DSP']}
digital_log=(ROOT/'build/regression/keyboard/tb_piano_13_debounce.log').read_text(encoding='utf-8-sig')
observed=re.search(r'to-PCM=(\d+)ns left-DAC-word=(\d+)ns',digital_log)
result={'baseline_commit':baseline['commit'],'top':'piano_13key_top','strict_verilog_files':compiled,
        'testbenches':tests,'testbench_count':sum(map(len,tests.values())),
        'unchanged_original_tests':preserved_tests,'clock_mhz':50,'worst_slack_ns':slacks,
        'constrained_ports':locations,'resources':resources,'cpu_pins_as_gpio':True,
        'digital_observation_ns':{'pcm':int(observed[1]),'left_dac_word':int(observed[2]),
                                  'scope':'single fresh C5 after stable input, not physical/analog latency or worst-case guarantee'},
        'bitstream':str(fs),'bitstream_sha256':hashlib.sha256(fs.read_bytes()).hexdigest(),
        'source_changes':changes,'programmed':False,'uploaded':False}
(OUT/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'PASS summary: {compiled} Verilog files, {result["testbench_count"]} benches, 23 placed ports, setup {slacks["setup"]:+.3f} ns, hold {slacks["hold"]:+.3f} ns')
print(f'Preserved {preserved_tests} original test files; review patch contains {len(changes)} changed/added files.')
