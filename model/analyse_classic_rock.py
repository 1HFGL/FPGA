"""Offline classic/legacy comparison. Reference-model previews, NOT board recordings.

Default run reconstructs the seven modal cases; --reuse-bus uses this run's cache
only if modal ROM and complete event configuration match its recorded identity.
The coherent-sine diagnostic includes aliasing, interpolation and quantization
spurs; it is deliberately not labelled a full-system alias rejection measurement.
"""
from pathlib import Path
import argparse,hashlib,json,math,wave
import numpy as np
from check_music_pipe import Model,load_config,ROOT
from gen_rock_v2_rom import CAB_ALPHA,shaper,ROCK_DRIVE_DENOMINATOR,ROCK_SHAPER_LEVEL

OUT=ROOT/'build/analysis/classic_candidate'
CASES={'C3':[48],'C4':[60],'C5':[72],'C6':[84],'power_C4':[60,67,72],'major_C4':[60,64,67,72],'stress16':list(range(48,80,2))}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def identity():return dict(modal_rom_sha256=sha(ROOT/'rtl/rom/piano_v3_modes.mem'),sine_sha256=sha(ROOT/'rtl/rom/sine_1024.mem'),cases=CASES,velocity=100,ratio=65536,hold_frames=18000,release_frames=6000)
def capture():
 table,sine=load_config();data={}
 for name,notes in CASES.items():
  model=Model(table,sine,len(notes));gate=(1<<len(notes))-1
  packed=sum(n<<(7*i) for i,n in enumerate(notes));vel=sum(100<<(7*i) for i in range(len(notes)))
  bus=[]
  for i in range(24000):
   model.step(gate if i<18000 else 0,0,0,packed,vel);bus.append(model.previous_input)
  data[name]=np.array(bus,dtype=np.int64)
  print('Captured dry bus',name,flush=True)
 np.savez(OUT/'dry_bus.npz',**data)
 (OUT/'dry_bus_identity.json').write_text(json.dumps(identity(),indent=2))
 return data
def fx(bus,lut):
 previous=a=b=0;audio=[];rail=0
 for x in bus.tolist():
  delta=(x-previous)//4
  for z in (previous+delta,previous+delta*2,previous+delta*3,x):
   y=lut[min(1023,abs(z)//32)]*(-1 if z<0 else 1)
   rail+=abs(y)>=lut[-1]*.95
   a+=((y*256-a)*CAB_ALPHA)//65536
   if y==0 and abs(a)<256:a=0
   b+=((a-b)*CAB_ALPHA)//65536
   if a==0 and abs(b)<256:b=0
  audio.append(b//2048);previous=x
 return np.array(audio,dtype=float),rail/(4*len(bus))*100
def rms(a):return float(np.sqrt(np.mean(a[64:18000]**2)))
def save_wav(path,values):
 samples=np.rint(values*8).astype(np.int64)
 assert np.max(np.abs(samples))<32768
 with wave.open(str(path),'wb') as w:
  w.setnchannels(1);w.setsampwidth(2);w.setframerate(48000);w.writeframes(samples.astype('<i2').tobytes())
def spur_ratio(samples,k):
 spec=np.abs(np.fft.rfft(samples))**2
 mask=np.ones(len(spec),dtype=bool);mask[0]=False
 mask[np.arange(k,len(spec),k)]=False
 return 10*math.log10(max(float(spec[mask].sum()),1e-30)/float(spec[1:].sum()))
def analyse(reuse):
 OUT.mkdir(parents=True,exist_ok=True)
 if reuse:
  assert json.loads((OUT/'dry_bus_identity.json').read_text())==identity(),'Dry capture identity mismatch'
  with np.load(OUT/'dry_bus.npz') as f:data={k:f[k] for k in CASES}
 else:data=capture()
 old=[round(12000*math.tanh(i*32/900)) for i in range(1024)];new=shaper()
 assert len(new)==1024 and new[0]==0 and max(new)==16100 and all(a<=b for a,b in zip(new,new[1:]))
 assert [int(s,16) for s in (ROOT/'rtl/rom/rock_v2_shaper.mem').read_text().split()]==new
 rows=[];old_preview=[];new_preview=[]
 for name,bus in data.items():
  a,ar=fx(bus,old);b,br=fx(bus,new)
  delta=20*math.log10(rms(b)/rms(a))
  if name in ('C3','C4','C5','C6'):assert abs(delta)<.15
  assert not a[-100:].any() and not b[-100:].any()
  rows.append(dict(case=name,notes=CASES[name],rms_difference_db=delta,legacy_peak=int(max(abs(a))),classic_peak=int(max(abs(b))),legacy_rail_percent=ar,classic_rail_percent=br))
  if name!='stress16':old_preview.extend(a);new_preview.extend(b)
 save_wav(OUT/'legacy_reference.wav',np.array(old_preview));save_wav(OUT/'classic_reference.wav',np.array(new_preview))
 diagnostic=[];N=8192
 for note in (48,60,72,84):
  for bend in (-2,0,2):
   f=440*2**((note+bend-69)/12);k=int(round(f*N/48000))|1
   for amplitude in (500,1500,4000):
    bus=np.rint(amplitude*np.sin(2*np.pi*k*np.arange(2*N)/N)).astype(np.int64)
    a,_=fx(bus,old);b,_=fx(bus,new)
    before=spur_ratio(a[-N:],k);after=spur_ratio(b[-N:],k)
    diagnostic.append(dict(note=note,bend_semitones=bend,actual_test_frequency_hz=k*48000/N,input_peak=amplitude,legacy_spurs_db=before,classic_spurs_db=after,change_db=after-before))
 change=np.array([r['change_db'] for r in diagnostic])
 report=dict(scope='Offline model and isolated fixed-point FX; not board audio or perceptual proof',curve=dict(denominator=ROCK_DRIVE_DENOMINATOR,level=ROCK_SHAPER_LEVEL),cases=rows,
  preview=dict(order=list(CASES)[:-1],seconds_per_case=.5,hold_seconds=.375,gain=8,note='Both previews use the SAME gain8 for audibility; this gain is not in the firmware.'),
  spectral_scope='36 coherent-sine cases at nearest odd FFT bins; energy outside all unfurled integer harmonics/DC includes folded harmonics, interpolation and quantization spurs. No assertion of alias-free audio.',
  spectral_summary=dict(cases=len(diagnostic),median_change_db=float(np.median(change)),minimum_change_db=float(change.min()),maximum_change_db=float(change.max()),improved_cases=int(sum(change<0))),spectral=diagnostic,
  sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),ROOT/'model/check_music_pipe.py',ROOT/'model/gen_rock_v2_rom.py',ROOT/'rtl/rom/rock_v2_shaper.mem',ROOT/'rtl/rom/piano_v3_modes.mem']})
 (OUT/'analysis.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(dict(cases=rows,spectral=report['spectral_summary']),indent=2),flush=True)
 print('PASS model checks: four anchor RMS within0.15dB, zero release tails, bounded WAVs, transfer ROM identity. Spectral figures are diagnostic only.')
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--reuse-bus',action='store_true');analyse(p.parse_args().reuse_bus)
