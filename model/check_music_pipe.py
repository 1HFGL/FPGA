"""Independent sample-level fixed-point oracle and export of actual RTL samples.

No Python synthesis is substituted for the capture. The oracle uses vector
equations, not the RTL scheduling state machine. ROM packing is checked against
the analytic preset generator; sine values are independently evaluated.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import wave
import numpy as np
from gen_piano_v3_rom import modes, shaper, CAB_ALPHA

ROOT=Path(__file__).resolve().parents[1]
U=65536


def load_config():
    table=np.array([[modes(p,n) for n in range(128)] for p in range(2)],dtype=np.int64)
    encoded=[int(s,16) for s in (ROOT/'rtl/rom/piano_v3_modes.mem').read_text().split()]
    expected=[(int(e)<<74)|(int(a)<<42)|(int(b)<<26)|(int(c)<<10)|int(d) for preset in table for note in preset for a,b,c,d,e in list(note)+[(0,0,1,0,0)]*16]
    assert encoded==expected, 'ROM parameter packing/order mismatch'
    encoded_amp=[int(s,16) for s in (ROOT/'rtl/rom/rock_v2_shaper.mem').read_text().split()]
    assert encoded_amp==shaper(), 'Amp transfer ROM differs'
    sine=np.array([int(math.copysign(math.floor(abs(32767*math.sin(2*math.pi*n/1024))+.5),math.sin(2*math.pi*n/1024))) for n in range(1024)],dtype=np.int64)
    actual=np.array([int(s,16) for s in (ROOT/'rtl/rom/sine_1024.mem').read_text().split()],dtype=np.int64)
    actual=np.where(actual>=32768,actual-65536,actual)
    assert np.array_equal(sine,actual), 'Independent sine formula differs'
    assert np.max(table[:,:,:,0])<2**31 and np.min(table[:,:,:,2])>0
    return table,sine


class Envelope:
    def __init__(self):
        self.level=0;self.state='idle';self.step=0;self.start=0;self.length=1
    def advance(self,gate,on,preset):
        if not gate:
            if self.level==0:self.state='idle'
            elif self.state!='release':
                self.state='release';self.step=0;self.start=self.level;self.length=4096 if preset else 2048
        elif on:
            self.state='attack';self.step=0;self.start=self.level;self.length=64 if preset else 16
        if self.state in ('attack','release'):
            self.step+=1
            if self.state=='attack':
                self.level=self.start+(U-self.start)*self.step//self.length
                if self.step==self.length:self.state='hold'
            else:
                self.level=self.start-self.start*self.step//self.length
                if self.step==self.length:self.state='idle'
        return self.level


class Model:
    def __init__(self,table,sine,n=16):
        self.n=n
        self.table=table;self.sine=sine
        self.phase=np.zeros((n,48),dtype=np.int64);self.amp=self.phase.copy()
        self.gate=np.zeros(n,dtype=bool);self.preset=np.zeros(n,dtype=np.int64)
        self.initialized=np.zeros(n,dtype=bool)
        self.last=np.zeros(n,dtype=np.int64);self.correction=self.last.copy();self.fade=self.last.copy()
        self.env=[Envelope() for _ in range(self.n)]
        self.lfsr=np.array([(0x1ace^(v*0x1234))&65535 for v in range(self.n)],dtype=np.int64)
        self.bend=np.zeros(n,dtype=np.int64)
        self.previous_input=0;self.cab_a=0;self.cab_b=0;self.shaper=shaper()
    def step(self,gate,trigger,preset,notes,velocity,gain=65536,ratio=65536):
        bits=lambda value:np.array([(value>>v)&1 for v in range(self.n)],dtype=np.int64)
        gate=bits(gate).astype(bool);on=gate & (bits(trigger).astype(bool) | ~self.gate)
        self.preset=np.where(on,bits(preset),self.preset)
        self.gate=gate
        note=np.array([(notes>>(7*v))&127 for v in range(self.n)])
        vel=np.array([(velocity>>(7*v))&127 for v in range(self.n)])
        cfg=self.table[self.preset,note]
        inc,amplitude,loss,initial_phase,noise=[cfg[:,:,k] for k in range(5)]
        noise_value=np.where(self.lfsr>=32768,self.lfsr-65536,self.lfsr)
        feedback=((self.lfsr>>15)^(self.lfsr>>13)^(self.lfsr>>12)^(self.lfsr>>10))&1
        self.lfsr=((self.lfsr<<1)|feedback)&65535
        self.bend=np.where(on,np.where(self.preset==0,512,0),np.maximum(0,self.bend-(self.bend>>9)-1))
        level=np.array([self.env[v].advance(gate[v],on[v],self.preset[v]) for v in range(self.n)],dtype=np.int64)
        env_active=np.array([e.state!='idle' for e in self.env])
        self.phase=np.where(on[:,None],initial_phase<<22,np.where(self.initialized[:,None],self.phase,0))
        self.amp=np.where(on[:,None],amplitude<<8,np.where((self.initialized & env_active)[:,None],self.amp,0))
        s=np.where(noise,noise_value[:,None],self.sine[self.phase>>22])
        partial=np.where(amplitude!=0,(s*(self.amp>>8))//32768,0)
        raw=((partial.sum(axis=1)*level)//U)*np.where(vel==127,128,vel)//128
        output=np.where(on,self.last,raw+(self.correction*self.fade)//64)
        output=np.where(env_active,np.clip(output,-32768,32767),0)
        self.correction=np.where(on,self.last-raw,self.correction)
        self.fade=np.where(on,63,np.maximum(self.fade-1,0))
        self.last=output
        delta=(self.amp*loss+(1<<24)-1)>>24
        self.amp=np.where((self.amp<256)|(self.amp<=delta),0,self.amp-delta)
        voice_ratio=(ratio*(65536+self.bend))//65536
        self.phase=(self.phase+(inc*voice_ratio[:,None])//65536)&0xffffffff
        self.initialized|=on
        active=gate|env_active|(output!=0)
        pack=lambda values,width:sum(int(x)<<(width*v) for v,x in enumerate(values))
        # Piano bypasses the nonlinear amplifier. Guitar voices interact in it.
        target=int(output[self.preset==0].sum())//4
        step=(target-self.previous_input)//4
        values=[self.previous_input+step*i for i in range(1,4)]+[target]
        self.previous_input=target
        for x in values:
            y=self.shaper[min(1023,abs(x)//32)]*(-1 if x<0 else 1)
            self.cab_a+=((y*256-self.cab_a)*CAB_ALPHA)//65536
            if y==0 and abs(self.cab_a)<256:self.cab_a=0
            self.cab_b+=((self.cab_a-self.cab_b)*CAB_ALPHA)//65536
            if self.cab_a==0 and abs(self.cab_b)<256:self.cab_b=0
        mixed=int(output[self.preset==1].sum())//8+self.cab_b//2048
        mixed=int(np.clip((mixed*gain)//65536,-32768,32767))
        return mixed,pack(active,1),pack(self.preset,1),pack(level,17),pack(output & 65535,16)


def check(path):
    table,sine=load_config();current=None;counts={};energy=np.zeros((2,16),dtype=np.int64);tail=[]
    with Path(path).open() as f:
        for row in csv.DictReader(f):
            epoch=int(row['epoch']);index=int(row['index'])
            if epoch!=current:current=epoch;model=Model(table,sine);model4=Model(table,sine,4);counts[epoch]=0
            assert index==counts[epoch], 'truncated/reordered capture'
            expect=model.step(*[int(row[k],16) for k in ['gate','trigger','preset','notes','velocity']])
            actual=(int(row['sample']),*[int(row[k],16) for k in ['active','selected','env','voices']])
            assert expect==actual,f'{epoch}/{index}: expected {expect}, got {actual}'
            expect4=model4.step(*[int(row[k],16) for k in ['gate','trigger','preset','notes','velocity']])
            actual4=(int(row['sample4']),*[int(row[k],16) for k in ['active4','selected4','env4','voices4']])
            assert expect4==actual4,f'four voices {epoch}/{index}: {expect4} != {actual4}'
            if epoch==0 and 40<=index<280:energy[0]+=np.abs(model.last)
            if epoch==0 and 400<=index<650:energy[1]+=np.abs(model.last)
            if epoch==0 and index>=10000:tail.append(actual[0])
            counts[epoch]+=1
    assert counts=={0:11000,1:400},counts
    assert (energy>0).all() and len(tail)==1000 and not any(tail)
    rows=list(csv.DictReader(Path(path).open()))
    baseline=json.loads((ROOT/'verification/fixtures/music_neutral_sha256.json').read_text())
    remap={'sample':'legacy_sample','sample4':'legacy_sample4'}
    digest=hashlib.sha256('\n'.join(','.join(row[remap.get(f,f)] for f in baseline['fields']) for row in rows).encode()).hexdigest()
    assert digest==baseline['sha256'],'Legacy 4/16 full-output/state golden changed'
    piano=[r for r in rows if int(r['epoch'])==0 and 400<=int(r['index'])<700]
    assert len(piano)==300 and all(r['sample']==r['legacy_sample'] and r['sample4']==r['legacy_sample4'] for r in piano)
    changed=sum(r['sample']!=r['legacy_sample'] for r in rows)
    assert changed>100,'Classic transfer did not affect the actual RTL output'
    report={'samples':sum(counts.values()),'per_voice_rock_energy':energy[0].tolist(),
            'per_voice_piano_energy':energy[1].tolist(),'sixteen_voice_bit_exact':True,
            'four_voice_reference_exact':True,'final_1000_samples_silent':True,'legacy_golden_exact':True,'piano_only_unchanged_frames':len(piano),'classic_changed_frames':changed}
    Path(path).with_suffix('.verification.json').write_text(json.dumps(report,indent=2))
    print('PASS independent music oracle: 11400 samples, 16 rock and 16 piano outputs, mixed presets, exact silence')
if __name__=='__main__':
    import sys
    check(sys.argv[1])
