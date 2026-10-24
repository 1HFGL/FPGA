"""Replay actual WCH reports and independent six-slot boundary/fault vectors."""
from pathlib import Path
import argparse,json,random,subprocess,hashlib
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/touch_driver_20261024'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--capture',type=Path,help='Optional RawInput JSONL capture; default is the committed raw-report fixture')
args=parser.parse_args()
source=args.capture or ROOT/'verification/data/touch_wch_1a86_e5e3_reports.hex'
lines=source.read_text(encoding='utf-8').splitlines()
real=[bytes.fromhex(json.loads(line)['hex'] if args.capture else line) for line in lines]
OUT.mkdir(parents=True,exist_ok=True)
assert all(len(b)==52 and b[0]==1 for b in real)
vectors=list(real);rng=random.Random(241024)
for n in range(200):
    b=bytearray(52);b[0]=1;b[51]=rng.randrange(7)
    for i,identity in enumerate(rng.sample(range(256),6)):
        start=1+8*i;b[start]=rng.randrange(2);b[start+1]=identity
        for offset in (2,4):b[start+offset:start+offset+2]=rng.randrange(4097).to_bytes(2,'little')
    vectors.append(bytes(b))
edge=bytearray(52);edge[0]=1;edge[51]=6
for i in range(6):
    start=1+8*i;edge[start]=1;edge[start+1]=i
    edge[start+2:start+4]=(4096 if i%2 else 0).to_bytes(2,'little')
    edge[start+4:start+6]=(0 if i%2 else 4096).to_bytes(2,'little')
vectors.append(bytes(edge))
for kind in range(4):
    bad=bytearray(edge)
    if kind==0:bad[0]=3
    elif kind==1:bad[51]=7
    elif kind==2:bad[10]=bad[2]
    else:bad[3:5]=(4097).to_bytes(2,'little')
    vectors.append(bytes(bad))
up=bytearray(edge)
for i in range(6):up[1+8*i]=0;up[3+8*i:7+8*i]=b'\xff'*4
vectors.append(bytes(up))
def reference(b):
    active=ids=xs=ys=0;seen=set();bad=b[0]!=1 or b[51]>6
    for i in range(6):
        p=1+8*i;identity=b[p+1];ids|=identity<<(i*8)
        if b[p]&1:
            x=int.from_bytes(b[p+2:p+4],'little');y=int.from_bytes(b[p+4:p+6],'little')
            bad|=identity in seen or x>4096 or y>4096;seen.add(identity)
            active|=1<<i;xs|=min(1023,x*1024//4096)<<(i*12);ys|=min(599,y*600//4096)<<(i*12)
    return (int(bad)<<198)|(ys<<126)|(xs<<54)|(ids<<6)|active
(OUT/'replay_input.mem').write_text(''.join(f'{int.from_bytes(b,"little"):0104x}\n' for b in vectors))
(OUT/'replay_expected.mem').write_text(''.join(f'{reference(b):050x}\n' for b in vectors))
sources=[ROOT/'rtl/usb/touch_report_decode.v',ROOT/'verification/tb/control/tb_touch_report_decode.v']
inputs={str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[source,Path(__file__)]}
cmd=['D:/iverilog/bin/iverilog.exe','-g2001','-s','tb_touch_report_decode','-o',str(OUT/'replay.vvp'),*map(str,sources)]
subprocess.run(cmd,cwd=ROOT,check=True)
result=subprocess.run(['D:/iverilog/bin/vvp.exe','-n',str(OUT/'replay.vvp'),f'+COUNT={len(vectors)}'],cwd=ROOT,capture_output=True,check=True)
body=result.stdout.decode();(OUT/'replay.log').write_bytes(result.stdout+result.stderr)
assert 'PASS tb_touch_report_decode' in body and 'FAIL' not in body,body
(OUT/'replay.json').write_text(json.dumps({'real_reports':len(real),'total_vectors':len(vectors),'status':'PASS','inputs':inputs},indent=2)+'\n')
print(body)
