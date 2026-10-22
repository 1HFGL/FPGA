"""Independent sample-domain integer reference; Python is never in the FPGA audio path."""
from collections import deque
from pathlib import Path
import argparse, json, math, random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/regression/reverb'
LENGTHS = (1499, 1601, 1747, 1879, 223, 563)
GAINS = (52, 51, 50, 49)

def tz(x, bits):
    return (abs(x) >> bits) * (-1 if x < 0 else 1)

def sat(x, bits=18):
    return max(-(1 << (bits-1)), min((1 << (bits-1))-1, x))

class Room:
    def __init__(self):
        self.q = [deque([0]*n) for n in LENGTHS]
        self.lp = [0]*4
        self.nonzero = 0
        self.saturations = 0

    def limit(self, x):
        y = sat(x)
        self.saturations += x != y
        return y

    def exchange(self, i, value):
        old = self.q[i].popleft()
        self.q[i].append(value)
        self.nonzero += (value != 0) - (old != 0)

    def tick(self, x, wet=32):
        delayed = [q[0] for q in self.q]
        for i in range(4):
            self.lp[i] = tz(self.lp[i] + delayed[i], 1)
            self.exchange(i, self.limit(tz(x, 1) + tz(self.lp[i]*GAINS[i], 6)))
        v = self.limit(sum(delayed[:4]))
        for i in (4, 5):
            y = self.limit(delayed[i] - tz(v, 1))
            self.exchange(i, self.limit(v + tz(y, 1)))
            v = y
        wet_sample = tz(v, 2)
        out = sat(x + tz((wet_sample-x)*wet, 7), 16)
        tail = self.nonzero != 0 or any(self.lp) or out != 0
        return out, int(tail), wet_sample

    def audit(self):
        assert self.nonzero == sum(v != 0 for q in self.q for v in q)

def vectors():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(20261017)
    # A reset starts each independent case, including dirty delay memory resets.
    cases = [
        ('zero', [0]*2000),
        ('positive_impulse', [32767]+[0]*71999),
        ('negative_impulse', [-32768]+[0]*71999),
        ('small_signal', [127]+[0]*47999),
        ('positive_dc', [32767]*12000+[0]*96000),
        ('negative_dc', [-32768]*12000+[0]*96000),
        ('random', [rng.randint(-32768, 32767) for _ in range(10000)]),
        ('reset_dirty', [0]*5000),
        ('alternating', [32767, -32768]*4096+[0]*72000),
    ]
    stats = {}
    count = 0
    with (OUT/'vectors.txt').open('w') as stream:
        for name, samples in cases:
            room=Room(); last=-1; first_wet=None; energy=[0]*15; tail_end=-1
            for n,x in enumerate(samples):
                y,active,w = room.tick(x)
                # WET_LEVEL=0 is exact dry; WET_LEVEL=128 is exact wet.
                a0 = int(room.nonzero != 0 or any(room.lp) or x != 0)
                a128 = int(room.nonzero != 0 or any(room.lp) or w != 0)
                stream.write(f'{int(n==0)} {x} {y} {active} {w} {a0} {a128}\n')
                if y: last=n
                if active: tail_end=n
                if w and first_wet is None:first_wet=n
                if n//4800<len(energy):energy[n//4800]+=w*w
                count+=1
            room.audit()
            if name not in ('random',):
                assert not active, (name, room.nonzero, room.lp)
            stats[name]={'samples':len(samples),'first_wet_sample':first_wet,
                'last_nonzero_output':last,'last_active':tail_end,'wet_energy_per_100ms':energy,
                'internal_saturations':room.saturations}
    stats['vectors']=count
    (OUT/'reference.json').write_text(json.dumps(stats,indent=2))
    print(f'PASS generated {count} independent room vectors including dirty RAM resets',flush=True)

def check_capture(path):
    import csv
    room=Room(); count=0; changed=0; tails=0; last_epoch=None
    with Path(path).open() as f:
        for row in csv.DictReader(f):
            epoch=int(row['epoch'])
            if epoch!=last_epoch:room=Room();last_epoch=epoch
            x=int(row['dry']);actual=int(row['wet']);out,_,_=room.tick(x)
            assert out==actual, (count,x,out,actual)
            changed+=out!=x;tails+=x==0 and out!=0;count+=1
    assert count>1000 and changed>100 and tails>100,(count,changed,tails)
    room.audit()
    report={'samples':count,'changed':changed,'wet_only_samples':tails}
    (OUT/'integration_reference.json').write_text(json.dumps(report,indent=2))
    print('PASS integrated reference '+json.dumps(report),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--capture');a=p.parse_args()
    if a.capture:check_capture(a.capture)
    else:vectors()
