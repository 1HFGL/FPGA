"""Run the production audit against isolated, deliberately broken netlists.

Fixtures contain only the netlist: each rejection must occur at the intended
structural check, before any later report files would be needed. Real build
artifacts are read-only. These mutation fixtures are not implementation proof.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
SOURCE = ROOT / 'projects/examples/instruments_board/impl/gwsynthesis/instruments_board.vg'
CHECKER = ROOT / 'model/check_presets_board.py'
original_bytes = SOURCE.read_bytes()
original = original_bytes.decode('utf-8')


def within_module(text, name, transform):
    pattern = r'(?ms)^module\s+' + re.escape(name) + r'\s*\(.*?^endmodule[^\n]*'
    found = re.search(pattern, text)
    assert found, name
    changed = transform(found[0])
    assert changed != found[0], name
    return text[:found.start()] + changed + text[found.end():]


def pin(text, kind, instance, name, value):
    pattern = r'\b' + re.escape(kind) + r'\s+' + re.escape(instance) + r'\s*\((.*?)\);'
    found = re.search(pattern, text, re.S)
    assert found, (kind, instance)
    changed, count = re.subn(r'\.' + re.escape(name) + r'\([^)]*\)',
                             '.' + name + '(' + value + ')', found[0])
    assert count == 1 and changed != found[0]
    return text[:found.start()] + changed + text[found.end():]


first_rom_module = re.search(r'(?ms)^module\s+(\w+)\s*\((?:(?!^endmodule).)*?\bpROM\s', original)[1]
cases = [
    ('rom_ce_tied_high', within_module(original, first_rom_module,
        lambda s: pin(s, 'pROM', 'rom_rom_0_0_s', 'CE', 'VCC')), 'sample CE mismatch'),
    ('hierarchy_wave_ce_tied_low', within_module(original, 'voice_instrument',
        lambda s: pin(s, 'instrument_wave', 'u_wave', 'error_acc_6_9', 'GND')), 'sample CE mismatch'),
    ('dac_frame_ce_tied_high', within_module(original, 'i2s_tx',
        lambda s: pin(s, 'DFFCE', 'active_sample_15_s0', 'CE', 'VCC')), 'DAC frame CE mismatch'),
    ('selector_ce_tied_high', within_module(original, 'instrument_wave',
        lambda s: pin(s, 'DFFRE', 'selected_s0', 'CE', 'VCC')), 'wave selected register'),
    ('request_anchor_tied_low', within_module(original, 'voice_bank_instruments',
        lambda s: pin(s, 'DFFRE', 'request_d1_s0', 'D', 'GND')), 'Invalid sample request source'),
    ('rom_clock_tied_high', within_module(original, first_rom_module,
        lambda s: pin(s, 'pROM', 'rom_rom_0_0_s', 'CLK', 'VCC')), 'sample clock mismatch'),
]
results = []
for label, changed, diagnostic in cases:
    project = OUT / 'mutations' / label
    netpath = project / 'impl/gwsynthesis/instruments_board.vg'
    netpath.parent.mkdir(parents=True, exist_ok=True)
    netpath.write_text(changed, encoding='utf-8')
    result = subprocess.run([sys.executable, str(CHECKER), '--project', str(project),
                             '--report', str(project / 'unexpected-pass.json')],
                            cwd=ROOT, text=True, capture_output=True)
    output = result.stdout + result.stderr
    (project / 'checker.log').write_text(output, encoding='utf-8')
    assert result.returncode != 0, (label, 'checker unexpectedly passed')
    assert diagnostic in output and 'AssertionError' in output, (label, output)
    assert 'FileNotFoundError' not in output and 'PASS:' not in output, (label, output)
    results.append({'case':label, 'returncode':result.returncode, 'expected_diagnostic':diagnostic,
                    'fixture_netlist_sha256':hashlib.sha256(netpath.read_bytes()).hexdigest()})
    print('PASS negative control:', label, 'exit', result.returncode)

assert SOURCE.read_bytes() == original_bytes, 'Production netlist changed during fixture tests'
summary = {'status':'PASS', 'production_checker_sha256':hashlib.sha256(CHECKER.read_bytes()).hexdigest(),
           'source_netlist_sha256':hashlib.sha256(original_bytes).hexdigest(),
           'production_netlist_unchanged':True, 'negative_controls':results}
(OUT / 'negative-controls.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
print('All six negative controls rejected through the original checker entry point.')
