"""1025 ratios for +/-2 semitones; unsigned Q1.16, center exactly 65536.
This ROM holds frequency ratios, never recorded audio.
"""
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]
def ratios():
    return [math.floor(65536*2**((code-512)/3072)+.5) for code in range(1025)]
def generate():
    data=ratios()
    assert data[512]==65536 and all(a<b for a,b in zip(data,data[1:]))
    (ROOT/'rtl/rom/pitch_bend_1025.mem').write_text('\n'.join(f'{x:05x}' for x in data)+'\n',encoding='ascii',newline='\n')
if __name__=='__main__':generate()
