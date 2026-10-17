"""Audit the Gowin 1.9.12.03 dual-instrument synthesis netlist.

Checks the 12 physical ROM tables, both layers of data selection, four
independent event registers and connections into the brightness/amplitude
datapath. The sine ROM is legally optimized to 15-bit sine >> 1 values;
the strings ROM moves under u_guitar when its wrapper is removed.
This is a structural/content audit, not gate-level timing simulation.
Unexpected mapping changes fail for review rather than being silently ignored.
"""
from pathlib import Path
import argparse
import hashlib
import itertools
import json
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--netlist', type=Path, default=ROOT / 'projects/checks/instruments_check/impl/gwsynthesis/instruments_check.vg')
parser.add_argument('--report', type=Path, default=ROOT / 'build/regression/logs/instrument_netlist_audit.json')
args = parser.parse_args()
text = args.netlist.read_text(encoding='utf-8')
modules = dict(re.findall(r'(?ms)^module\s+(\w+)\s*\((.*?)^endmodule[^\n]*', text))


def block(body, kind, instance):
    match = re.search(r'\b' + re.escape(kind) + r'\s+' + re.escape(instance) + r'\s*\((.*?)\);', body, re.S)
    assert match, (kind, instance)
    return {p: re.sub(r'\s+', '', n) for p, n in re.findall(r'\.([\w]+)\(([^)]*)\)', match[1])}


def child(body, instance):
    match = re.search(r'\b(\w+)\s+' + re.escape(instance) + r'\s*\(', body)
    assert match, instance
    name = match[1]
    return name, modules[name], block(body, name, instance)


def table(path):
    data = path.read_text(encoding='ascii').split()
    assert len(data) == 1024 and all(re.fullmatch(r'[0-9A-Fa-f]{4}', w) for w in data), path
    return [int(w, 16) for w in data]


tables = {name: table(ROOT / 'rtl/rom' / f'{name}_1024.mem') for name in ('sine', 'guitar', 'strings')}
tables['base'] = [((n if n < 32768 else n - 65536) >> 1) & 32767 for n in tables['sine']]
assert tables['guitar'] != tables['strings']
records = []
lut_count = 0
truth_cases = 0


def check_mux(body, instance, out, first, second, select):
    global lut_count, truth_cases
    pins = block(body, 'LUT3', instance)
    init = int(re.search(r'defparam\s+' + re.escape(instance) + r"\.INIT=8'h([0-9A-Fa-f]+)", body)[1], 16)
    assert pins['F'] == out
    assert {pins[f'I{x}'] for x in range(3)} == {first, second, select}
    for a, b, s in itertools.product((0, 1), repeat=3):
        values = {first: a, second: b, select: s}
        idx = sum(values[pins[f'I{x}']] << x for x in range(3))
        assert (init >> idx) & 1 == (b if s else a), (instance, values)
        truth_cases += 1
    lut_count += 1


for v, suffix in enumerate(('', '_0', '_1', '_2')):
    sound = modules['voice_instrument' + suffix]
    wave_name, wave, wave_pins = child(sound, 'u_wave')
    base_name, base, base_pins = child(wave, 'u_sine')
    pair_name, pair, pair_pins = child(wave, 'u_guitar')
    assert wave_pins['requested_instrument'] == 'requested_instrument'
    assert wave_pins['full_sample_Z'] == 'full_sample_Z[15:0]'
    assert wave_pins['base_sample'] == 'base_sample[14:0]'
    assert base_pins['base_sample'] == 'base_sample[14:0]'
    for label, module, body, instance, output in (
        ('base', base_name, base, 'rom_rom_0_0_s', 'base_sample[14:0]'),
        ('guitar', pair_name, pair, 'rom_rom_0_0_s', 'guitar_sample[15:0]'),
        ('strings', pair_name, pair, 'rom_rom_0_1_s', 'strings_sample[15:0]')):
        parts = re.findall(r'defparam\s+' + instance + r"\.INIT_RAM_([0-9A-Fa-f]{2})=256'h([0-9A-Fa-f]+);", body)
        assert len(parts) == 64, (module, instance)
        words = []
        for idx, (number, value) in enumerate(parts):
            assert int(number, 16) == idx
            words.extend((int(value, 16) >> (16 * offset)) & 65535 for offset in range(16))
        assert words == tables[label], (v, label, 'ROM contents mismatch')
        pins = block(body, 'pROM', instance)
        assert output in pins['DO']
        assert pins['CLK'] == 'clk_d' and pins['CE'] == 'sample_request_q'
        assert pins['AD'] == '{addr[9:0],GND,GND,VCC,VCC}'
        records.append({'voice': v, 'kind': label, 'module': module, 'instance': instance, 'verified_words': len(words)})
    for label in ('guitar', 'strings'):
        assert pair_pins[label + '_sample'] == label + '_sample[15:0]'
    for bit in range(16):
        mid = f'full_sample_Z_{bit}_3'
        check_mux(wave, f'full_sample_Z_{bit}_s0', mid,
                  f'guitar_sample[{bit}]', f'strings_sample[{bit}]', 'selected')
        check_mux(wave, f'full_sample_Z_{bit}_s', f'full_sample_Z[{bit}]',
                  f'base_sample[{min(bit, 14)}]', mid, 'allow_harmonics')
    selected = block(wave, 'DFFRE', 'selected_s0')
    assert selected['Q'] == 'selected' and selected['D'] == 'requested_instrument'
    assert selected['CLK'] == 'clk_d' and selected['CE'] == 'sample_request_q'
    harmonic = block(wave, 'DFFRE', 'allow_harmonics_s0')
    assert harmonic['Q'] == 'allow_harmonics' and harmonic['CE'] == 'sample_request_q'
    pending = block(sound, 'DFFRE', 'pending_instrument_s0')
    active = block(sound, 'DFFRE', 'active_instrument_s0')
    assert pending['D'] == f'instrument_q[{v}]'
    assert active['Q'] == f'instrument_core[{v}]' and active['D'] == 'event_instrument'
    # The selected ROM output, same-phase base and brightness all feed one
    # registered multiplier, whose output is added back to the delayed base.
    shape_dsps = []
    for inst in re.findall(r'\bMULTALU27X18\s+(\w+)\s*\(', sound):
        dsp = block(sound, 'MULTALU27X18', inst)
        if 'full_sample_Z' in dsp['A']:
            assert 'base_sample' in dsp['D'] and 'tone_core' in dsp['B']
            assert 'tone_product' in dsp['DOUT'] and dsp['CE'] == '{VCC,request_d1}'
            shape_dsps.append(inst)
    assert len(shape_dsps) == 1
    _, _, amplitude = child(sound, 'u_amplitude')
    assert amplitude['shaped'] == 'shaped[15:0]' and amplitude['env_d1'] == 'env_d1[16:0]'

assert len(re.findall(r'(?m)^\s+pROM\s', text)) == 12
synlog = args.netlist.with_suffix('.log').read_text(encoding='utf-8')
warnings = [line for line in synlog.splitlines() if re.search(r'\bWARN\b', line)]
assert len(warnings) == 4 and all('NL0002' in w and 'u_strings' in w for w in warnings), warnings
report = {
    'status': 'PASS', 'netlist': str(args.netlist.resolve()),
    'netlist_sha256': hashlib.sha256(args.netlist.read_bytes()).hexdigest(),
    'scope': 'Synthesis structural/content audit; not post-route simulation',
    'roms': records, 'verified_rom_words': sum(r['verified_words'] for r in records),
    'selector_lut_bits': lut_count, 'selector_truth_cases': truth_cases,
    'independent_event_register_pairs': 4, 'brightness_datapath_connections': 4,
    'amplitude_datapath_connections': 4, 'warnings': warnings,
    'conclusion': '12 physical pROMs remain. Sine tables are optimized to exact signed half-sine in 15 bits; guitar/strings tables retain exact full words. Only the four u_strings wrapper hierarchies were removed.'
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print('PASS: 12 physical pROMs, 12288 exact mapped words (4 half-sine + 4 guitar + 4 strings).')
print(f'PASS: {lut_count} selector LUT bits, {truth_cases} truth cases, 4 independent event register pairs and brightness/amplitude datapaths.')
print('Resolved: 4 NL0002 u_strings warnings remove hierarchy only; all strings ROM data remains.')
print('Report:', args.report.resolve())
