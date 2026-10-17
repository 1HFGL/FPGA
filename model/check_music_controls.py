"""Independent control slew, frequency-ratio and per-sample audio oracle."""
from pathlib import Path
import csv,hashlib,json,math,sys
import numpy as np
from check_music_pipe import Model,load_config,ROOT
def ramp(value,target,step):return min(value+step,target) if value<target else max(value-step,target)
def check(path):
 table,sine=load_config()
 ratios=[math.floor(65536*math.exp(math.log(2)*(n-512)/3072)+.5) for n in range(1025)]
 actual=[int(x,16) for x in (ROOT/'rtl/rom/pitch_bend_1025.mem').read_text().split()]
 assert actual==ratios and actual[512]==65536
 error=max(abs(1200*math.log2(r/65536)-(n-512)*200/512) for n,r in enumerate(actual))
 assert error<.02
 epoch=None;counts={};mute=0;tail=0;max_gain_step=0;max_bend_step=0
 for row in csv.DictReader(Path(path).open()):
  e=int(row['epoch']);i=int(row['index'])
  if e!=epoch:
   epoch=e;model=Model(table,sine);g=4096;b=512;v=8;target=512;counts[e]=0
  assert i==counts[e]
  if i==100:v,target=64,1024
  if i==300:v,target=0,0
  if i==500:v,target=127,512
  if i==900:v,target=127,1024
  if i>1100 and i<1200 and i%7==0:v,target=i%128,(i*17)%1025
  if i==1250:v,target=33,0
  if i==1500:v,target=127,1024
  if i==1600:v,target=64,0
  assert (int(row['volume']),int(row['bend']))==(v,target),(e,i,'targets')
  assert (int(row['gain']),int(row['bend_current']),int(row['ratio']))==(g,b,ratios[b]),(e,i,'slew')
  expect=model.step(*[int(row[k],16) for k in ['gate','trigger','preset','notes','velocity']],gain=g,ratio=ratios[b])
  actual_audio=(int(row['sample']),*[int(row[k],16) for k in ['active','selected','env','voices']])
  assert expect==actual_audio,(e,i,expect,actual_audio)
  if 440<=i<490:assert expect[0]==0 and np.abs(model.last).sum()>0;mute+=1
  if e==0 and 1600<=i<2000:assert (model.phase!=0).any();tail+=1
  if e==0 and i>=5700:assert expect[0]==0
  ng=ramp(g,65536 if v==127 else v*512,512);nb=ramp(b,target,8)
  max_gain_step=max(max_gain_step,abs(ng-g));max_bend_step=max(max_bend_step,abs(nb-b));g,b=ng,nb
  if i==950:v,target=0,0 # accepted after this request, affects the following ramp step
  counts[e]+=1
 assert counts=={0:6000,1:1500} and mute==100 and tail==400
 result=dict(samples=7500,bit_exact=True,ratio_max_error_cents=error,max_gain_step=max_gain_step,max_bend_step=max_bend_step,mute_frames=mute,tail_bend_frames=tail)
 Path(path).with_suffix('.verification.json').write_text(json.dumps(result,indent=2))
 # Old default controls are a regression contract, not a second active core.
 baseline=json.loads((ROOT/'verification/fixtures/music_neutral_sha256.json').read_text())
 rows=list(csv.DictReader((ROOT/'build/regression/music/tb_music_pipe.csv').open()))
 digest=hashlib.sha256('\n'.join(','.join(row[{'sample':'legacy_sample','sample4':'legacy_sample4'}.get(f,f)] for f in baseline['fields']) for row in rows).encode()).hexdigest()
 assert digest==baseline['sha256'],'Legacy transfer no longer reproduces the original baseline'
 print(f'PASS control oracle: 7500 exact samples; ratio error {error:.6f} cents; 11400 legacy-transfer frames unchanged')
if __name__=='__main__':check(sys.argv[1])
