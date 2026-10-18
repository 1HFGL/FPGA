"""Sample-domain references for chorus, echo and their cascade with the existing room.
No RTL schedule is used; delay queues start at zero, unlike the uninitialized FPGA RAM.
"""
from collections import deque
from pathlib import Path
import argparse, csv, hashlib, json, math, random
from check_room_reverb import Room, tz, sat

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/regression/effects'

class Chorus:
    def __init__(self):
        self.q=deque([0]*1024);self.phase=[0,0x40000000];self.nonzero=0
        self.delay_q8=(0,0)
    def tick(self,x,level=24):
        taps=[];delays=[]
        for k,(phase,base) in enumerate(zip(self.phase,(512,768))):
            triangle=min(phase,0xffffffff-phase)
            delay=base*256+triangle//65536;delays.append(delay)
            d,f=divmod(delay,256)
            a,b=self.q[-d],self.q[-d-1]
            taps.append(a+tz((b-a)*f,8))
        wet=tz(sum(taps),1)
        y=sat(x+tz((wet-x)*level,7),16)
        old=self.q.popleft();self.q.append(x)
        self.nonzero+=(x!=0)-(old!=0)
        self.phase=[(p+s)&0xffffffff for p,s in zip(self.phase,(53687,74267))]
        self.delay_q8=tuple(delays)
        return y,int(self.nonzero!=0 or y!=0),wet
    def audit(self):assert self.nonzero==sum(x!=0 for x in self.q)

class Echo:
    def __init__(self):self.q=deque([0]*7680);self.nonzero=0
    def tick(self,x,level=16):
        delayed=self.q.popleft()
        written=sat(tz(20*x+3*delayed,3))
        self.q.append(written);self.nonzero+=(written!=0)-(delayed!=0)
        wet=tz(delayed,2)
        y=sat(x+tz((wet-x)*level,7),16)
        return y,int(self.nonzero!=0 or y!=0),wet
    def audit(self):assert self.nonzero==sum(x!=0 for x in self.q)

def vectors():
    OUT.mkdir(parents=True,exist_ok=True)
    rng=random.Random(20261018)
    cases=[('zero',[0]*9000),('positive_impulse',[32767]+[0]*109999),
           ('negative_impulse',[-32768]+[0]*109999),('small_signal',[127]+[0]*89999),
           ('positive_dc',[32767]*10000+[0]*110000),('negative_dc',[-32768]*10000+[0]*110000),
           ('random',[rng.randint(-32768,32767) for _ in range(22000)]),('dirty_reset',[0]*10000),
           ('modulation',[round(20000*math.sin(2*math.pi*440*n/48000)) for n in range(160000)]+[0]*100000)]
    count=0;report={}
    with (OUT/'vectors.txt').open('w') as stream:
        for name,inputs in cases:
            chorus=Chorus();echo=Echo();last_c=-1;last_e=-1;last_tail_c=-1;last_tail_e=-1
            dmins=[10**9]*2;dmaxs=[0]*2
            echoes=[]
            for n,x in enumerate(inputs):
                c,ct,cw=chorus.tick(x);e,et,ew=echo.tick(x)
                stream.write(f'{int(n==0)} {x} {c} {ct} {cw} {e} {et} {ew}\n')
                count+=1
                if c:last_c=n
                if e:last_e=n
                if ct:last_tail_c=n
                if et:last_tail_e=n
                if name=='positive_impulse' and n%7680==0:echoes.append((n,e))
                for k,d in enumerate(chorus.delay_q8):dmins[k]=min(dmins[k],d);dmaxs[k]=max(dmaxs[k],d)
            chorus.audit();echo.audit()
            if name!='random':assert not ct and not et,(name,ct,et)
            report[name]={'samples':len(inputs),'last_chorus':last_c,'last_echo':last_e,
                          'last_chorus_active':last_tail_c,'last_echo_active':last_tail_e,
                          'chorus_min_delay_q8':dmins,'chorus_max_delay_q8':dmaxs}
            if echoes:report[name]['echoes']=echoes
    assert report['positive_impulse']['echoes'][1][0]==7680
    report['vectors']=count;report['vectors_sha256']=hashlib.sha256((OUT/'vectors.txt').read_bytes()).hexdigest()
    (OUT/'reference.json').write_text(json.dumps(report,indent=2))
    print(f'PASS generated {count} independent chorus/delay vectors incl. multiple LFO turns/wraps',flush=True)

def capture(path):
    c=Chorus();e=Echo();r=Room();last=None;count=0;echo_only=0;wet_only=0;changed_c=0;changed_e=0
    with Path(path).open() as stream:
        for row in csv.DictReader(stream):
            epoch=int(row['epoch'])
            if epoch!=last:c=Chorus();e=Echo();r=Room();last=epoch
            x=int(row['dry']);cy,_,_=c.tick(x);ey,_,_=e.tick(cy);ry,_,_=r.tick(ey)
            actual=tuple(int(row[n]) for n in ('chorus','delay','wet'))
            assert (cy,ey,ry)==actual,(count,(cy,ey,ry),actual)
            changed_c+=cy!=x;changed_e+=ey!=cy;echo_only+=cy==0 and ey!=0;wet_only+=x==0 and ry!=0;count+=1
    assert count>10000 and echo_only>100 and changed_c>1000 and changed_e>1000,(count,echo_only)
    c.audit();e.audit();r.audit()
    report={'samples':count,'chorus_changed':changed_c,'delay_changed':changed_e,'echo_only':echo_only,'wet_only':wet_only}
    (OUT/'integration_reference.json').write_text(json.dumps(report,indent=2))
    print('PASS three-effect cascade reference '+json.dumps(report),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--capture');a=p.parse_args()
    if a.capture:capture(a.capture)
    else:vectors()
