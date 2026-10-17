"""Verify octave evidence against current inputs, then package the two local images."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'verification/evidence/octaves'
FINAL = ROOT / 'build/regression/final'
PACK = ROOT / 'build/audition/octave3_j13_20261017'
reviewed = {}

def require(ok, message):
    if not ok:
        raise SystemExit('FAIL octave audit: ' + message)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def check_input(name, digest):
    path = ROOT / name
    require(path.is_file() and sha(path) == digest.lower(), 'stale input ' + str(path))
    if path.is_relative_to(ROOT) and not path.relative_to(ROOT).as_posix().startswith('build/'):
        reviewed[path.relative_to(ROOT).as_posix()] = digest.lower()

def manifest(path):
    count = 0
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        match = re.fullmatch(r'([a-fA-F0-9]{64})  (.+)', line)
        if match:
            check_input(match[2], match[1]); count += 1
    require(count > 20, 'incomplete manifest ' + str(path))
    return count

OUT.mkdir(parents=True, exist_ok=True)
PACK.mkdir(parents=True, exist_ok=True)
tests = {}
for tag in ('tb_panel_octaves', 'tb_performance_octaves', 'tb_hdmi_octaves',
            'tb_final_performance_legacy', 'tb_final_display_ui', 'tb_final_hdmi_isolation'):
    inputs = json.loads((FINAL/(tag+'_inputs.json')).read_text(encoding='utf-8-sig'))
    for name, digest in inputs['sha256'].items():
        check_input(name, digest)
    log = FINAL/(tag+'_console.log')
    body = log.read_text(errors='replace')
    passed = [line for line in body.splitlines() if 'PASS '+tag.removesuffix('_legacy') in line]
    require(passed and not re.search(r'\bFAIL\b|\*\* (Error|Fatal):', body), 'test '+tag)
    shutil.copyfile(log, OUT/(tag+'.log'))
    tests[tag] = {'pass': passed, 'dependencies': len(inputs['sha256']), 'mode': inputs['mode'],
                  'input_manifest_sha256': sha(FINAL/(tag+'_inputs.json'))}

strict = manifest(ROOT/'build/regression/strict/strict_inputs.txt')
require(strict == 158, 'strict source inventory changed')
shutil.copyfile(ROOT/'build/regression/strict/strict_compile.log', OUT/'strict.log')
protected = []
for record in json.loads((ROOT/'verification/data/protected_inputs.json').read_text(encoding='utf-8-sig')):
    name = record['path']
    if name.startswith(('verification/tb/', 'upstream/')) or name.endswith('.sdc') or \
       Path(name).name in ('process_config.json','hdmi_reset_placement.cst','hdmi.cst') or \
       name in ('rtl/display/dvi_tx_gowin.v','rtl/display/hdmi_clock_60k.v',
                'rtl/display/hdmi_reset_guard.v','rtl/display/tmds_encoder.v','verification/data/display_font_golden.mem'):
        protected.append(name)
        reviewed[name] = sha(ROOT/name)
imports = json.loads((ROOT/'verification/data/upstream_imports.json').read_text(encoding='utf-8-sig'))
for record in imports:
    reviewed[record['path']] = sha(ROOT/record['path'])
# Older manifests were made on a different checkout and contain LF/CRLF-dependent hashes.
# Use this turn's Git base for preservation; current simulations/builds still require exact byte hashes.
preserved = sorted(set(protected+[record['path'] for record in imports]))
changed = subprocess.check_output(['git','diff','--name-only','HEAD','--',*preserved],cwd=ROOT,text=True)
require(not changed.strip(), 'protected baseline content changed: '+changed)
unchanged = subprocess.check_output(['git','diff','--name-only','HEAD','--',
    'rtl/synth','rtl/rom','rtl/control','rtl/audio','boards','upstream',
    'projects/hdmi','projects/piano','verification/data'], cwd=ROOT, text=True)
require(not unchanged.strip(), 'core/ROM/constraints/process/upstream changed: '+unchanged)
old_tests = subprocess.check_output(['git','diff','--name-only','HEAD','--','verification/tb'], cwd=ROOT, text=True)
require(not old_tests.strip(), 'existing test changed: '+old_tests)

hdmi = json.loads((ROOT/'build/hdmi/implementation_check.json').read_text(encoding='utf-8-sig'))
require(hdmi['status']=='PASS_CURRENT_CONSTRAINTS_ONLY' and not hdmi['errors'], 'HDMI gate')
for item in hdmi['inputs']:
    check_input(item['path'], item['sha256'])
builds = {}
for name, folder, base, dest in (
    ('hdmi', ROOT/'build/hdmi', ROOT/'projects/hdmi/impl/pnr/piano_hdmi', 'hdmi_octave3_j13.fs'),
    ('noscreen', ROOT/'build/octaves-noscreen', ROOT/'projects/piano/impl/pnr/piano_performance', 'piano_octave3_j13.fs')):
    timing_path = folder/('timing.txt' if name=='hdmi' else 'timing_from_html.txt')
    timing = timing_path.read_text(encoding='utf-8-sig')
    slacks = {}
    for section in ('3.1.1 Setup Paths Table','3.1.2 Hold Paths Table','3.1.3 Recovery Paths Table',
                    '3.1.4 Removal Paths Table','3.2 Minimum Pulse Width Table'):
        require('\n'+section+'\n' in timing, 'missing timing '+section)
        table = timing.split('\n'+section+'\n',1)[1].strip().split('\n\n',1)[0]
        values = re.findall(r'^\s*\d+\s+(-?\d+\.\d+)\s+',table,re.M)
        require(values and min(map(float, values))>=0, 'negative/missing slack '+name+section)
        slacks[section] = min(map(float,values))
    manifest(folder/'build_inputs.txt')
    report = Path(str(base)+'.rpt.txt').read_text(encoding='utf-8-sig')
    resources = {}
    for resource in ('Logic','Register','BSRAM','DSP'):
        match = re.search(r'\b'+resource+r'\s*\|\s*(\d+(?:\.\d+)?)/(\d+)', report)
        require(match is not None, 'missing resource '+resource)
        resources[resource] = {'used':float(match[1]),'available':int(match[2])}
    fs = Path(str(base)+'.fs')
    require('Bitstream generation completed' in (folder/'build.log').read_text(errors='replace'), 'incomplete build '+name)
    if name=='hdmi':
        require(sha(fs)==hdmi['bitstream_sha256'], 'HDMI image changed')
    else:
        require(sha(fs).upper() in (folder/'artifact.txt').read_text(encoding='utf-8-sig'), 'no-screen gate stale')
    project = ROOT/('projects/hdmi' if name=='hdmi' else 'projects/piano')
    effective = project/('impl/piano_hdmi_process_config.json' if name=='hdmi' else 'impl/uart_piano_process_config.json')
    require(sha(project/'process_config.json')==sha(effective), 'process config changed '+name)
    shutil.copyfile(fs, PACK/dest)
    require(sha(fs)==sha(PACK/dest), 'package copy changed')
    builds[name] = {'resources': resources, 'worst_slack_ns': slacks, 'fs': (PACK/dest).relative_to(ROOT).as_posix(),
                    'fs_sha256':sha(fs), 'bytes':fs.stat().st_size, 'programmed':False}
    for source, target in [(timing_path,name+'_timing.txt'),(folder/'build_inputs.txt',name+'_build_inputs.txt'),
                           (folder/'build.log',name+'_build.log'),(Path(str(base)+'.rpt.txt'),name+'_resources.txt')]:
        shutil.copyfile(source,OUT/target)

pins = ROOT/'build/octaves-noscreen/j13-check.json'
pin_data = json.loads(pins.read_text(encoding='utf-8-sig'))
require(pin_data['status']=='PASS_PIN_CONTRACT_ONLY', 'J13 actual report gate')
require(len(pin_data['reports'])==2, 'missing J13 implementation report')
for name, digest in pin_data['reports'].items():
    require(sha(ROOT/name)==digest, 'J13 report changed '+name)
shutil.copyfile(pins,OUT/'j13-check.json')
reviewed[Path(__file__).relative_to(ROOT).as_posix()] = sha(__file__)
summary = {'date':'2026-10-17', 'base_revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    'working_tree_changes':True, 'board':'Tang Mega60K / NEO Dock31005 / current J13 harness',
    'tools':{'simulation':'ModelSim SE-64 10.6e','implementation':'Gowin V1.9.12.03'},
    'controls':{'KEY0':'reset piano/middle','KEY1':'middle -> high -> low -> middle; once per press',
        'KEY2':'piano/classic rock, range retained','brightness_enabled':False,'uart':'absolute MIDI; independent host octave selector'},
    'note_ranges':{'low':[48,60],'middle':[60,72],'high':[72,84]},
    'sample_contract':{'core_valid':923,'output_cache':924,'lead_half_edges':60},
    'tests':tests, 'strict_verilog_2001_files':strict, 'builds':builds,
    'protected_inputs_unchanged_from_base':len(protected), 'upstream_imports_unchanged_from_base':len(imports),
    'preservation_method':'Git diff against base_revision (LF/CRLF checkout normalization); exact current byte hashes in source_sha256 and all simulation/build manifests.',
    'core_rom_constraints_process_old_tests_unchanged_from_base':True,
    'source_sha256':reviewed, 'evidence_sha256':{p.name:sha(p) for p in sorted(OUT.iterdir()) if p.is_file() and p.name!='summary.json'},
    'hardware_verified':False,
    'limits':['Existing PR1014 generic clock routing; full DAC external timing and analog end-to-end latency unresolved.',
              '158-file compilation and six simulations are current; unchanged A/PC suites were not rerun.',
              'New performance test accelerates UART/debounce; HDMI octave test uses the actual 2ms key debounce with injected ADC values.',
              'Octave selection is not counted as a new third expression dimension; brightness is deferred by user request.']}
(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(PACK/'manifest.json').write_text(json.dumps({'builds':builds,'source_sha256':reviewed,
    'evidence_summary_sha256':sha(OUT/'summary.json'),'hardware_verified':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(PACK/'试听说明.txt').write_text('''三音区试听包（2026-10-17）
硬件：Tang Mega60K + NEO Dock31005，原13键/双旋钮J13接线，无须改线。
有HDMI屏：hdmi_octave3_j13.fs；无屏：piano_octave3_j13.fs。
下载器用SRAM Program选择相应.fs；.gprj是工程，不是直接下载文件。

KEY0：复位到钢琴、中音区。
KEY1：每按一次，中→高→低→中，长按只跳一次。KEY2切钢琴/经典摇滚，保留音区。
低音区13音：C3 C#3 D3 D#3 E3 F3 F#3 G3 G#3 A3 A#3 B3 C4。
中音区13音：C4 C#4 D4 D#4 E4 F4 F#4 G4 G#4 A4 A#4 B4 C5。
高音区13音：C5 C#5 D5 D#5 E5 F5 F#5 G5 G#5 A5 A#5 B5 C6。
八白键模块仍按C/D/E/F/G/A/B/C，黑键模块仍为C#/D#/F#/G#/A#。

试听通过标准（先低音量，弯音居中）：
1. 两种乐器分别切遍三档，每档逐一弹13键；每键有声音、松开能结束，音高依次升高。
2. 同一键换高档应升高一八度，低档降低一八度；钢琴和摇滚均可辨认。
3. 按住旧音再换区，旧音不突变，新按的另一键采用新档；松开后无卡音。
4. 每档弹四音和弦，逐个松开；其它音不被误关。换区后重复，快速重按不丢音/卡音。
5. HDMI音区名和琴键名同步；吉他高档显示12～24品。画面只高亮当前音区的持有音。
6. KEY2换乐器不改变音区；KEY0恢复钢琴/中档；两个旋钮继续调音量与弯音。
7. 上位机音区仍在电脑选择；KEY1不对UART绝对音符重复移调。

当前明亮度暂不启用，KEY1不再调明暗。核心音色参数未改。
已完成仿真、综合和当前约束下布局布线检查；尚未代为上板，以上听感/接线/模拟总延迟需要实测。
每份文件SHA256见同目录manifest.json；完整证据见verification/evidence/octaves/summary.json。
''',encoding='utf-8-sig')
print('PASS octave audit/package: six simulations, 158 strict files, two implementations; hardware pending.')
for name,data in builds.items():
    print(name, data['fs_sha256'], data['worst_slack_ns'], data['resources'])
