"""Independent integer vectors for raw hysteresis and the display-only level scale."""
import hashlib
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/controls_meter_20261024'
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(20261024)
held = [None, None]
vectors = []
for n in range(20000):
    if n % 100 == 0:
        target = [rng.randrange(32768), rng.randrange(32768)]
    if n < 1024:
        raw = [min(32767, n*32), max(0, 32767-n*32)]
    elif n < 2048:
        raw = [16384+rng.randrange(-200, 201), 16384+rng.randrange(-200, 201)]
    else:
        raw = [max(0, min(32767, x+rng.randrange(-384, 385))) for x in target]
    reset = n % 997 == 0
    if reset:
        held = [None, None]
    for ch in range(2):
        value = raw[ch]
        if ch == 1 and 16128 <= value < 16640:
            held[ch] = 16384
        elif held[ch] is None or value in (0, 32767) or abs(value-held[ch]) > 384:
            held[ch] = value
    packed = (int(reset)<<44) | (raw[1]<<29) | (raw[0]<<14) | ((held[1]//256)<<7) | (held[0]//256)
    vectors.append(f'{packed:012x}')
(OUT/'knob_reference.hex').write_text('\n'.join(vectors)+'\n', encoding='ascii')

def scale(value):
    if value >= 32768:
        return 128
    if value < 32:
        return value//4
    exponent = value.bit_length()-1
    fractional_sixteenths = ((value-(1<<exponent))*16)//(1<<exponent)
    return 8+12*(exponent-5)+(3*fractional_sixteenths)//4

(OUT/'meter_reference.hex').write_text(''.join(f'{scale(x):02x}\n' for x in range(65536)), encoding='ascii')
sources = [ROOT/x for x in ('rtl/control/adc_knob_if.v', 'rtl/display/display_feedback.v',
                           'verification/tb/control/tb_controls_reference.v')]
hashes = {str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sources}
image = OUT/'reference.vvp'
compiled = subprocess.run(['D:/iverilog/bin/iverilog.exe','-g2001','-s','tb_controls_reference',
                          '-o',str(image),*map(str,sources)], cwd=ROOT, capture_output=True, check=True)
result = subprocess.run(['D:/iverilog/bin/vvp.exe','-n',str(image)],cwd=ROOT,capture_output=True,check=True)
body = result.stdout.decode()
(OUT/'reference.log').write_bytes(compiled.stdout+compiled.stderr+result.stdout+result.stderr)
assert 'PASS tb_controls_reference' in body and 'FAIL' not in body, body
(OUT/'reference.json').write_text(json.dumps({'status':'PASS','knob_vectors':20000,
    'meter_values':65536,'seed':20261024,'inputs':hashes},indent=2)+'\n',encoding='utf-8')
print(body)
