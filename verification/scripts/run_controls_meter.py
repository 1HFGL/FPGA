"""Targeted Verilog-2001 checks using Icarus; does not replace ModelSim strict checks."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--bin', default='D:/iverilog/bin')
p.add_argument('--simlib', default='D:/Library/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v')
p.add_argument('--out', default='build/controls_meter_20261024')
p.add_argument('--timeout', type=int, default=600)
p.add_argument('--functional-rom', action='store_true', help='Use qualified simulation-only ROM view (never for Gowin)')
p.add_argument('tops', nargs='*')
a = p.parse_args()
OUT = ROOT / a.out
OUT.mkdir(parents=True, exist_ok=True)
rtl = sorted((ROOT / 'rtl').rglob('*.v'))
tops = a.tops or ['tb_knob_antijitter', 'tb_meter_scale', 'tb_display_feedback',
                 'tb_simple_ui_states', 'tb_slider_controls_filtered',
                 'tb_controls_meter_hdmi', 'tb_three_key_chords', 'tb_review_hdmi_reset_recovery']
test_paths = {x.stem: x for x in (ROOT / 'verification/tb').rglob('*.v')}

def run(top):
    sources = rtl + [test_paths[top]]
    extra_inputs = []
    if a.functional_rom or top == 'tb_merge32_rom_equivalence':
        from functional_dual_rom import generate
        model, data = generate(ROOT, OUT/top)
        physical = ROOT/'rtl/rom/modal_coeff_rom_dual.v'
        sources = [model if x==physical else x for x in sources]
        extra_inputs = data + [physical, ROOT/'verification/scripts/functional_dual_rom.py',ROOT/'rtl/rom/piano_v3_modes.mem']
        if top == 'tb_merge32_rom_equivalence':
            vendor = OUT/'modal_coeff_rom_dual_vendor.v'
            vendor.write_bytes(physical.read_bytes().replace(b'module modal_coeff_rom_dual(',b'module modal_coeff_rom_dual_vendor('))
            sources.append(vendor)
        else:
            certificate = json.loads((ROOT/'verification/evidence/usb_touch/rom_qualification.json').read_text(encoding='utf-8'))
            assert certificate['status']=='PASS'
            certificate_inputs = {k.replace('\\','/'):v for k,v in certificate['inputs'].items()}
            for path in ('rtl/rom/modal_coeff_rom_dual.v','verification/scripts/functional_dual_rom.py','rtl/rom/piano_v3_modes.mem'):
                assert certificate_inputs[path]==hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),path
    if top in ('tb_slider_controls_filtered', 'tb_slider_guide_hdmi', 'tb_controls_meter_hdmi'):
        sources.append(test_paths['tb_slider_controls'])
    if top in ('tb_dual16_core', 'tb_dual16_snapshot'):
        original = subprocess.check_output(['git','show','f314bc066a428b7f43b19c0c8fa1586e6a98dc24:rtl/synth/voice_bank_music_pipe.v'],cwd=ROOT)
        frozen = OUT / (top + '_serial_reference.v')
        frozen.write_bytes(original.replace(b'module voice_bank_music_pipe #(', b'module voice_bank_music_serial_reference #('))
        sources.append(frozen)
    if top == 'tb_event_encoder_equivalence':
        original = subprocess.check_output(['git','show','36b81ab2983ef04823784c95a345e4383c2b2724:rtl/control/event_encoder.v'],cwd=ROOT)
        frozen = OUT / 'event_encoder_reference.v'
        frozen.write_bytes(original.replace(b'module event_encoder #(', b'module event_encoder_reference #('))
        sources.append(frozen)
    if 'hdmi' in top or 'dual16' in top or top in ('tb_three_key_chords','tb_merge32_rom_equivalence'):
        sources.append(Path(a.simlib))
    hashes = {str(x.relative_to(ROOT)) if x.is_relative_to(ROOT) else str(x):
              hashlib.sha256(x.read_bytes()).hexdigest() for x in sources+extra_inputs}
    image = OUT / (top + '.vvp')
    cmd = [str(Path(a.bin) / 'iverilog.exe'), '-g2001', '-s', top, '-o', str(image)]
    cmd += [str(x) for x in sources]
    compiled = subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=120)
    (OUT / (top + '_compile.log')).write_bytes(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        raise RuntimeError(top + ' compile failed')
    try:
        result = subprocess.run([str(Path(a.bin) / 'vvp.exe'), '-n', str(image)],
                                cwd=ROOT, capture_output=True, timeout=a.timeout)
    except subprocess.TimeoutExpired as error:
        (OUT / (top + '.log')).write_bytes((error.stdout or b'') + (error.stderr or b'') + b'\nINCOMPLETE: host simulation timed out\n')
        raise
    log = result.stdout + result.stderr
    (OUT / (top + '.log')).write_bytes(log)
    body = log.decode('utf-8', errors='replace')
    expected = 'tb_slider_controls' if top == 'tb_slider_controls_filtered' else top
    passed = re.search(r'PASS:?\s+'+re.escape(expected)+r'\b', body)
    if top == 'tb_voice_allocator':
        passed = 'PASS: tb_voice_allocator_32' in body
    if result.returncode or re.search(r'\bFAIL\b|ERROR:|FATAL:', body) or not passed:
        raise RuntimeError(top + ' failed: ' + body[-1200:])
    evidence = {'top': top, 'status': 'PASS', 'flags': '-g2001', 'functional_rom':a.functional_rom,
                'inputs': hashes,
                'results': [line for line in body.splitlines() if 'PASS ' in line or 'max_settled_ns=' in line]}
    (OUT / (top + '_inputs.json')).write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    print('\n'.join(evidence['results']), flush=True)
    return evidence

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, tops))
(OUT / 'regression.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
print('PASS targeted checks:', len(results), flush=True)
