"""Reproducible coefficients and independent response checks for the brightness control.

0..126 sweep each pole's -3 dB corner logarithmically from 400 Hz to 12 kHz.
127 is the original sound. No instrument ROM, sample precision or output gain changes.
"""
from pathlib import Path
import argparse
import csv
import json
import math
import random
import re
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/brightness_response'
START = '    // BEGIN GENERATED BRIGHTNESS CURVE (model/brightness_response.py)'
END = '    // END GENERATED BRIGHTNESS CURVE'


def coefficient(value):
    if value == 127:
        return 65536
    hz = 400 * 30 ** (value / 126)
    d = 1 - math.cos(2 * math.pi * hz / 48000)
    return round((math.sqrt(d * (d + 2)) - d) * 65536)


def generated():
    return '\n'.join([START, '    function [16:0] perceptual_alpha;',
                      '        input [6:0] value;', '        begin case(value)'] +
                     [f"            7'd{b}: perceptual_alpha=17'd{coefficient(b)};" for b in range(128)] +
                     ["            default: perceptual_alpha=17'd65536;",
                      '        endcase end', '    endfunction', END])


def check_curve(write=False):
    source = ROOT / 'rtl/audio/tone_filter.v'
    text = source.read_text(encoding='utf-8')
    begin, finish = text.index(START), text.index(END) + len(END)
    if write:
        source.write_text(text[:begin] + generated() + text[finish:], encoding='utf-8')
    else:
        assert text[begin:finish] == generated(), 'Regenerate the brightness coefficient table'
    values = [coefficient(b) for b in range(128)]
    assert all(0 < a < b <= 65536 for a, b in zip(values, values[1:]))


def rounded(value):
    return (1 if value >= 0 else -1) * ((abs(value) + 32768) // 65536)


def pole(x, b, state, legacy=False):
    a = (65536 if b == 127 else 2048 + 500*b) if legacy else coefficient(b)
    state += rounded((x*65536-state)*a)
    if x == 0 and abs(state) < 32768:
        state = 0
    return state, max(-32768, min(32767, rounded(state)))


def vectors():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(20261024)
    rows = []
    for b in range(128):
        for n in range(64):
            x = [32767,-32768,0,1,-1][n] if n < 5 else rng.randrange(-32768,32768)
            rows.append((x,b,rng.randrange(6,15),int(n == 0),-1))
    # Coherent three-tone probes: warm up, then capture an exact 4096-sample window.
    for segment,b in enumerate([0,32,64,96,127]):
        for n in range(1024+4096):
            x = round(sum(4000*math.sin(2*math.pi*k*n/4096) for k in [22,85,341]))
            rows.append((x,b,8,int(n == 0),segment if n >= 1024 else -1))
    rows += [(0,0,8,0,-1)]*1024
    (OUT/'vectors.txt').write_text(''.join(' '.join(map(str,r))+'\n' for r in rows),encoding='ascii')
    print('Generated brightness samples:',len(rows))


def check_samples():
    rows = [tuple(map(int,s.split())) for s in (OUT/'vectors.txt').read_text().splitlines()]
    actual = list(csv.DictReader((OUT/'actual.csv').open()))
    assert len(actual) == len(rows), (len(actual),len(rows))
    first=second=legacy=0
    for i,((x,b,gap,reset,segment),got) in enumerate(zip(rows,actual)):
        if reset:first=second=legacy=0
        first,y1=pole(x,b,first)
        second,y2=pole(y1,b,second)
        legacy,old=pole(x,b,legacy,True)
        assert int(got['index'])==i and int(got['new'])==y2 and int(got['old'])==old,(i,got,y2,old)
        if b==127:assert y2==x==old,(i,'original tone changed')
    assert first==second==legacy==0,'Tail did not reach exact silence'
    spectra=[]
    for segment,b in enumerate([0,32,64,96,127]):
        indices=[i for i,r in enumerate(rows) if r[4]==segment]
        before=np.array([rows[i][0] for i in indices],dtype=float)
        new=np.array([int(actual[i]['new']) for i in indices],dtype=float)
        old=np.array([int(actual[i]['old']) for i in indices],dtype=float)
        assert len(new)==4096
        spectra_in=np.abs(np.fft.rfft(before))
        gains={}
        for name,signal in [('old',old),('new',new)]:
            spec=np.abs(np.fft.rfft(signal))
            gains[name]=[float(20*np.log10(spec[k]/spectra_in[k])) for k in [22,85,341]]
        spectra.append({'brightness':b,'frequencies_hz':[48000*k/4096 for k in [22,85,341]],'gain_db':gains})
    # These are audible-band spectral requirements, not merely "some PCM changed".
    assert spectra[0]['gain_db']['new'][2] < -38
    assert spectra[0]['gain_db']['new'][2] < spectra[0]['gain_db']['old'][2]-12
    assert spectra[2]['gain_db']['new'][2] < spectra[2]['gain_db']['old'][2]-8
    assert all(spectra[i+1]['gain_db']['new'][2]-spectra[i]['gain_db']['new'][2] > 3 for i in range(4))
    result={'exact_samples':len(rows),'spectra':spectra,'silence_exact':True,'bypass_127_exact':True,
            'hardware_listening_verified':False}
    (OUT/'response.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS brightness integer reference, spectral contrast and full-range response:',len(rows))
    for s in spectra:print(s['brightness'],s['gain_db'])


def check_hdmi():
    from check_delay_chorus import Chorus, Echo
    from check_room_reverb import Room
    rows=list(csv.DictReader((OUT/'hdmi.csv').open()))
    previous=None
    first=second=legacy=0
    phases={}
    for i,row in enumerate(rows):
        epoch=int(row['epoch'])
        if epoch!=previous:
            first=second=legacy=0
            c,e,r=Chorus(),Echo(),Room()
            previous=epoch
        x,b=int(row['raw']),int(row['brightness'])
        first,y1=pole(x,b,first)
        second,y2=pole(y1,b,second)
        legacy,old=pole(x,b,legacy,True)
        cy,_,_=c.tick(y2)
        ey,_,_=e.tick(cy)
        ry,_,_=r.tick(ey)
        expected=(old,y2,cy,ey,ry)
        actual=tuple(int(row[k]) for k in ('old','new','chorus','delay','output'))
        assert expected==actual,(i,epoch,expected,actual)
        if b==127:assert x==old==y2,(i,'127 bypass')
        phase=phases.setdefault(row['phase'],{'samples':0,'changed':0,'nonzero':0})
        phase['samples']+=1
        phase['changed']+=y2!=old
        phase['nonzero']+=x!=0
    assert len(rows)>4000
    for phase in ('1','2','5','6'):
        assert phases[phase]['changed']>200,(phase,phases[phase])
    result={'samples':len(rows),'phases':phases,'five_stages_exact':True,
            'original_127_exact':True,'hardware_listening_verified':False}
    (OUT/'hdmi_reference.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('PASS HDMI original/new tone, chorus, delay and room integer reference:',len(rows))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['generate','check','vectors','analyze','hdmi'])
    a=p.parse_args()
    check_curve(a.action=='generate')
    if a.action=='vectors':vectors()
    if a.action=='analyze':check_samples()
    if a.action=='hdmi':check_hdmi()
    if a.action in ['generate','check']:print('PASS brightness curve: 128 monotonic coefficients; 127 exact bypass')
