"""Audit the Gowin 1.9.12.03 KEY1/KEY2 instrument audition build.

Checks mapped ROM contents, lane-0 preset switching, the declared timing
constraints and all eight board pins. This is structural/content + STA review,
not post-route simulation or a measurement of the external DAC interface.
Unexpected changes in Gowin mapping fail explicitly and need fresh review.
"""
from pathlib import Path
import argparse
import hashlib
import html
import itertools
import json
import re

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--project', type=Path, default=ROOT / 'fpga_project/instruments_board')
p.add_argument('--report', type=Path, default=ROOT / 'results/logs/presets_board_audit.json')
a = p.parse_args()
project = a.project.resolve()
name = 'instruments_board'
netpath = project / f'impl/gwsynthesis/{name}.vg'
net = netpath.read_text(encoding='utf-8')
modules = dict(re.findall(r'(?ms)^module\s+(\w+)\s*\((.*?)^endmodule[^\n]*', net))

def block(body, kind, instance):
    m = re.search(r'\b' + re.escape(kind) + r'\s+' + re.escape(instance) + r'\s*\((.*?)\);', body, re.S)
    assert m, (kind, instance)
    return {k: re.sub(r'\s+', '', v) for k,v in re.findall(r'\.(\\?[^\s(]+)\s*\(([^)]*)\)', m[1])}

def child(body, instance):
    m = re.search(r'\b(\w+)\s+' + re.escape(instance) + r'\s*\(', body)
    assert m, instance
    return m[1], modules[m[1]], block(body, m[1], instance)

def table(kind):
    data = (ROOT / f'rtl/rom/{kind}_1024.mem').read_text(encoding='ascii').split()
    assert len(data) == 1024 and all(re.fullmatch('[0-9a-fA-F]{4}', w) for w in data)
    return [int(w,16) for w in data]

expected = {kind: table(kind) for kind in ('sine','guitar','strings')}
expected['base'] = [((v if v < 32768 else v-65536) >> 1) & 32767 for v in expected['sine']]
assert expected['guitar'] != expected['strings']
roms = []
for mod, body in modules.items():
    for inst in re.findall(r'\bpROM\s+(\w+)\s*\(', body):
        parts = re.findall(r'defparam\s+' + inst + r"\.INIT_RAM_([0-9a-fA-F]{2})=256'h([0-9a-fA-F]+);", body)
        assert len(parts) == 64, (mod, inst)
        data = []
        for i,(number,value) in enumerate(parts):
            assert int(number,16) == i
            data.extend((int(value,16)>>(16*k))&65535 for k in range(16))
        matches = [kind for kind in ('base','guitar','strings') if expected[kind] == data]
        assert len(matches) == 1, (mod, inst, 'unrecognized ROM')
        pins = block(body,'pROM',inst)
        assert pins['CLK'] == 'sys_clk_d' and pins['CE'] == 'error_acc_6_7'
        assert pins['AD'] == '{addr[9:0],GND,GND,VCC,VCC}'
        roms.append({'module':mod,'instance':inst,'kind':matches[0],'words':len(data),'output':pins['DO']})
assert len(roms) == 9
assert {k:sum(r['kind']==k for r in roms) for k in ('base','guitar','strings')} == {'base':4,'guitar':4,'strings':1}

# Follow the physical KEY2 input through the debouncer, toggling register,
# bank/lane-0, event snapshot registers, and the registered ROM selection.
top = modules['instrument_presets_top']
keybuf = block(top,'IBUF','Key_in_1_ibuf')
_,_,key = child(top,r'\g_key[1].u_key')
select = block(top,'DFFRE','selected_instrument_s1')
invert = block(top,'INV','n27_s2')
assert keybuf == {'O':'Key_in_d[1]','I':'Key_in[1]'}
assert key['Key_in_d'] == keybuf['O'] and key['key_press'] == select['CE']
assert select['Q'] == invert['I'] == 'selected_instrument' and select['D'] == invert['O']
assert re.search(r"defparam selected_instrument_s1.INIT=1'b0;",top)
_,bank,bankpins = child(top,'u_bank')
_,sound,soundpins = child(bank,r'\g_voice[0].u_voice')
assert bankpins['selected_instrument'] == soundpins['selected_instrument'] == select['Q']
pending = block(sound,'DFFRE','pending_instrument_s0')
active = block(sound,'DFFRE','active_instrument_s0')
assert pending['D'] == 'selected_instrument' and active['D'] == 'event_instrument'
event = block(sound,'LUT4','event_instrument_s1')
assert event['F'] == active['D'] and pending['Q'] in event.values() and 'selected_instrument' in event.values()
_,wave,wavepins = child(sound,'u_wave')
wave_sel = block(wave,'DFFRE','selected_s0')
assert wave_sel['D'] == wavepins['requested_instrument'] == 'requested_instrument'
assert wave_sel['CLK'] == 'sys_clk_d' and wave_sel['CE'] == 'error_acc_6_7'
assert active['Q'] in block(sound,'LUT3','requested_instrument_s0').values()
base_name,_,base_pins = child(wave,'u_sine')
pair_name,_,pair_pins = child(wave,'u_guitar')
assert {(r['kind'],r['output'].split(',')[-1]) for r in roms if r['module'] in (base_name,pair_name)} == {
    ('base','base_sample[14:0]}'),('guitar','guitar_sample[15:0]}'),('strings','strings_sample[15:0]}')}
assert base_pins['base_sample'] == wavepins['base_sample'] == 'base_sample[14:0]'
for kind in ('guitar','strings'):
    assert pair_pins[kind+'_sample'] == kind+'_sample[15:0]'
guard_register = block(bank,'DFFRE',r'\g_voice[0].velocity_d0_6_s0')
assert guard_register['D'] == 'VCC' and guard_register['CE'] == 'error_acc_6_7'
truth_cases = 0
guard_cases = 0
for bit in range(16):
    inst = f'full_sample_Z_{bit}_s0'
    pins = block(wave,'LUT3',inst)
    init = int(re.search(r'defparam\s+'+inst+r"\.INIT=8'h([0-9a-fA-F]+)",wave)[1],16)
    first,second,sel = f'guitar_sample[{bit}]',f'strings_sample[{bit}]',wave_sel['Q']
    assert pins['F'] == f'full_sample_Z_{bit}_3'
    assert {pins[f'I{i}'] for i in range(3)} == {first,second,sel}
    for g,s,choice in itertools.product((0,1),repeat=3):
        values={first:g,second:s,sel:choice}
        ix=sum(values[pins[f'I{i}']]<<i for i in range(3))
        assert (init>>ix)&1 == (s if choice else g)
        truth_cases += 1
    outer = block(wave,'LUT3',f'full_sample_Z_{bit}_s')
    assert outer['F'] == f'full_sample_Z[{bit}]' and pins['F'] in outer.values()
    outer_init=int(re.search(r'defparam\s+'+f'full_sample_Z_{bit}_s'+r"\.INIT=8'h([0-9a-fA-F]+)",wave)[1],16)
    for base,full,enabled in itertools.product((0,1),repeat=3):
        values={f'base_sample[{min(bit,14)}]':base,pins['F']:full,guard_register['Q']:enabled}
        ix=sum(values[outer[f'I{i}']]<<i for i in range(3))
        assert (outer_init>>ix)&1 == (full if enabled else base)
        guard_cases += 1
shape = block(sound,'MULTALU27X18','n682_s')
assert 'full_sample_Z' in shape['A'] and 'base_sample' in shape['D'] and 'tone_level_flat' in shape['B']
assert shape['CE'] == '{VCC,request_d1}' and 'tone_product' in shape['DOUT']
_,_,amplitude = child(sound,'u_amplitude')
assert amplitude['shaped'] == 'shaped[15:0]' and amplitude['env_d1'] == 'env_d1[16:0]'

# Read HTML tables, including the vendor's omitted closing td tags.
def rows(text):
    return [[html.unescape(re.sub('<[^>]+>','',c)).strip() for c in re.findall(r'<t[dh]\b[^>]*>(.*?)(?=</t[dh]>|<t[dh]\b|</tr>|$)',tr,re.S|re.I)] for tr in re.findall(r'<tr\b[^>]*>(.*?)</tr>',text,re.S|re.I)]
def section(text, label):
    return rows(text.split('name="'+label+'"',1)[1].split('<table',1)[1].split('</table>',1)[0])
# Every mapped clock input is the single constrained fabric clock or an
# unused DSP clock tied to ground; no unreported second domain is accepted.
assert set(re.findall(r'\.CLK\(([^)]*)\)',net)) == {'sys_clk_d','{GND,sys_clk_d}','{GND,GND}'}
sta = (project / f'impl/pnr/{name}_tr_content.html').read_text(encoding='utf-8')
summary = {r[0]:r[1] for r in rows(sta)[:30] if len(r)==2}
assert summary['Part Number']=='GW5AT-LV60PG484AC1/I0' and summary['Device Version']=='B'
assert int(summary['Numbers of Setup Violated Endpoints']) == int(summary['Numbers of Hold Violated Endpoints']) == 0
clock = section(sta,'Clock_Report')
assert len(clock)==2 and clock[1][1]=='sys_clk' and clock[1][3:5]==['20.000','50.000']
timing={}
for kind in ('Setup','Hold','Recovery','Removal'):
    paths=section(sta,kind+'_Slack_Table')[1:]
    assert paths and all(float(r[1])>=0 for r in paths)
    worst=min(paths,key=lambda r:float(r[1]))
    timing[kind.lower()]={'slack_ns':float(worst[1]),'from':worst[2],'to':worst[3],'data_delay_ns':float(worst[8])}
    if kind=='Setup':
        internal=[r for r in paths if r[4] == r[5] == 'sys_clk:[R]']
        assert internal
        timing['internal_setup_ns']=min(float(r[1]) for r in internal)
mpw=section(sta,'MIN_PULSE_WIDTH_TABLE')[1:]
assert mpw and all(float(r[1])>=0 for r in mpw)
timing['min_pulse_width_slack_ns']=min(float(r[1]) for r in mpw)
timing['fmax_mhz']=float(section(sta,'Max_Frequency_Report')[1][3].split('(')[0])
assert all(float(r[2])==0 and int(r[3])==0 for r in section(sta,'Total_Negative_Slack_Report')[1:])
expected_sdc=[
 'create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]',
 'set_false_path -from [get_ports {Key_in[0] Key_in[1]}]',
 'set_false_path -from [get_ports {sys_rst_n}]',
 'set_max_delay -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN}] 20.000',
 'set_min_delay -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN}] 0.000']
sdc=section(sta,'SDC_Report')[1:]
assert [r[2] for r in sdc] == expected_sdc and all(r[1]=='Actived' for r in sdc)
assert [l.strip() for l in (project/'clock.sdc').read_text().splitlines() if l.strip() and not l.strip().startswith('#')] == expected_sdc
pins=section((project/f'impl/pnr/{name}.pin.html').read_text(),'Pinout_by_Port_Name')
expected_pins={'sys_clk':('V22/7','in','LVCMOS33'),'sys_rst_n':('AA13/9','in','LVCMOS15'),'Key_in[0]':('AB13/9','in','LVCMOS15'),'Key_in[1]':('Y12/9','in','LVCMOS15'),'HP_BCK':('Y17/7','out','LVCMOS33'),'HP_WS':('AB17/7','out','LVCMOS33'),'HP_DIN':('AA16/7','out','LVCMOS33'),'PA_EN':('AB16/7','out','LVCMOS33')}
assert len(pins)==9 and {r[0] for r in pins[1:]}==set(expected_pins)
for r in pins[1:]:
    assert r[3]=='Y' and (r[2],r[4],r[7])==expected_pins[r[0]],r
    if r[4]=='out': assert r[8]=='8'
    elif r[0]!='sys_clk': assert r[9]=='UP'

config=json.loads((project/'process_config.json').read_text())
assert config['Correct_Hold_Violation'] and config['Run_Timing_Driven'] and config['PRINT_BSRAM_VALUE']
assert config['TopModule']=='instrument_presets_top' and config['OUTPUT_BASE_NAME']==name
actual_config=json.loads((project/f'impl/{name}_process_config.json').read_text())
for key in ('Correct_Hold_Violation','Run_Timing_Driven','PRINT_BSRAM_VALUE','TopModule','OUTPUT_BASE_NAME'):
    assert actual_config[key]==config[key],key
warnings={}
for label,rel in [('synthesis',f'impl/gwsynthesis/{name}.log'),('pnr',f'impl/pnr/{name}.log')]:
    lines=(project/rel).read_text(errors='replace').splitlines()
    assert not [l for l in lines if re.search(r'\bERROR\b|error:',l,re.I)]
    warnings[label]=[l for l in lines if re.search(r'\bWARN\b|warning:',l,re.I)]
assert len(warnings['synthesis'])==14 and all('NL0002' in w for w in warnings['synthesis'])
assert len(warnings['pnr'])==1 and 'PR1014' in warnings['pnr'][0]
resources=(project/f'impl/pnr/{name}.rpt.txt').read_text().split('3. Resource Usage Summary',1)[1].split('4. I/O Bank',1)[0].strip()
assert re.search(r'--pROM\s+\|\s+9\b',resources) and re.search(r'I/O Port\s+\|\s+8/',resources)
fs=project/f'impl/pnr/{name}.fs'
assert fs.is_file() and fs.stat().st_size>100000
sha=lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
source_hashes={}
source_paths=[]
for rel in re.findall(r'<File path="([^"]+)"',(project/f'{name}.gprj').read_text()):
    path=(project/rel).resolve(); source_hashes[str(path.relative_to(ROOT))]=sha(path)
    source_paths.append(path)
for path in [project/'process_config.json',project/'run.tcl',project/f'{name}.gprj',*(ROOT/'rtl/rom'/f'{k}_1024.mem' for k in ('sine','guitar','strings'))]:
    source_hashes[str(path.relative_to(ROOT))]=sha(path)
    source_paths.append(path)
# 常见的过期报告应拒绝；构建日志、位流和源码哈希须一并保存。
report_time=(project/f'impl/pnr/{name}_tr_content.html').stat().st_mtime_ns
assert not [str(path) for path in source_paths if path.stat().st_mtime_ns>report_time], 'Source changed after report; rebuild Gowin first.'
result={'status':'PASS','created_time':summary['Created Time'],'tool':summary['Tool Version'],'device':summary['Part Number'],'device_version':'B','timing':timing,'active_sdc':sdc,'pins':[dict(zip(pins[0],r)) for r in pins[1:]],'paths_analyzed':int(summary['Numbers of Paths Analyzed']),'endpoints_analyzed':int(summary['Numbers of Endpoints Analyzed']),'setup_violations':0,'hold_violations':0,'roms':roms,'rom_words_checked':sum(r['words'] for r in roms),'lane0_preset_lut_truth_cases':truth_cases,'lane0_base_full_lut_truth_cases':guard_cases,'lane0_dynamic_key2_event_and_audio_path_checked':True,'resource_summary':resources,'warnings':warnings,'source_sha256':source_hashes,'netlist_sha256':sha(netpath),'fs_sha256':sha(fs),'fs_bytes':fs.stat().st_size,'scope':'KEY1 C4 fixed-velocity single playable lane; KEY2 selects guitar/strings for next note. Three inactive lanes partially remain after optimization; retained ROMs do not prove playable polyphony. Timing covers internal 50 MHz logic and existing 20/0 ns register-to-pad budgets; async keys and external reset only are false-pathed. No external DAC setup/hold signoff, post-route simulation, or hardware download is claimed. PR1014 non-dedicated clock routing remains.'}
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(f"PASS: setup {timing['setup']['slack_ns']:+.3f} ns; internal setup {timing['internal_setup_ns']:+.3f} ns; hold {timing['hold']['slack_ns']:+.3f} ns; MPW {timing['min_pulse_width_slack_ns']:+.3f} ns.")
print('PASS: 8 constrained pins; 5 active expected SDC commands; 9 mapped ROMs / 9216 exact words; lane-0 KEY2 selection and 128 LUT truth cases.')
print('Retained warning: PR1014; external DAC timing and on-board listening are outside this audit.')
print('Report:',a.report.resolve())
