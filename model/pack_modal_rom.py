"""Losslessly bank the existing modal coefficients for two reads per clock.

Only slots 0..47 are used by both cores; slots 48..63 are not synthesized.
No quantization, parameter fitting or change of oscillator count occurs here.
Run --check before builds; run without --check to regenerate after ROM changes.
"""
from pathlib import Path
import argparse, hashlib
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
source=root/'rtl/rom/piano_v3_modes.mem'
words=source.read_text(encoding='ascii').splitlines()
assert len(words)==16384
assert all(0<=int(w,16)<(1<<75) for w in words)
for lane,name in enumerate(('even','odd')):
    packed=[words[record*64+pair*2+lane] for record in range(256) for pair in range(24)]
    target=root/f'rtl/rom/modes_{name}.mem'
    if args.check:
        assert target.read_text(encoding='ascii').splitlines()==packed, f'Stale bank: {target}'
    else:
        target.write_text('\n'.join(packed)+'\n',encoding='ascii',newline='\n')
print('PASS modal banks: all 12288 used coefficients unchanged; source sha256='+hashlib.sha256(source.read_bytes()).hexdigest())
