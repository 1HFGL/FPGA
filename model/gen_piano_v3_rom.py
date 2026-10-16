"""Measured spectral envelopes + analytic modal strings. No PCM in ROM.
Reference extraction and raw-file provenance: model/piano_reference_fit.json and model/piano_reference_sources.json.
C3..C6 logarithmic interpolation; outside anchors clamp spectral shape.
"""
from pathlib import Path
import json,math
from gen_rock_v2_rom import guitar_modes,shaper,CAB_ALPHA
ROOT=Path(__file__).resolve().parents[1];FS=48000
FIT=json.loads((ROOT/'model/piano_reference_fit.json').read_text())
def profile(note):
 n=max(48,min(84,note));i=min(2,int((n-48)//12));t=(n-FIT[i]['note'])/12
 a,b=FIT[i],FIT[i+1]
 blend=lambda x,y:math.exp((1-t)*math.log(max(x,1e-7))+t*math.log(max(y,1e-7)))
 return [blend(x,y) for x,y in zip(a['weights'],b['weights'])],[blend(x,y) for x,y in zip(a['tau'],b['tau'])],blend(a['stiffness'],b['stiffness'])
def modes(preset,note):
 if preset==0:return guitar_modes(note)+[(0,0,1,0,0)]*16
 f=440*2**((note-69)/12);weights,taus,B=profile(note);result=[]
 # First 24 partials + two detuned companions in the audible lower bands.
 # The three decay rates approximate the measured evolving spectral envelope;
 # this remains uncoupled modal synthesis, not a full soundboard simulation.
 for count,cents,gain,offset,life in [(24,0,1,0,.85),(12,-1.3,.48,9,1.15),(10,1.0,.34,1018,1.32)]:
  for h in range(1,count+1):
   divisor=1+(.48 if h<=12 else 0)+(.34 if h<=10 else 0)
   amplitude=weights[h-1]*gain/divisor
   if weights[h-1]<.0008:amplitude=0
   hz=f*h*math.sqrt((1+B*h*h)/(1+B))*2**(cents/1200)
   # Hammer position gives partial polarity, unlike an identical-phase sawtooth.
   phase=(offset+(512 if math.sin(math.pi*.137*h)<0 else 0))%1024
   result.append((hz,amplitude,max(.05,taus[h-1]*life),phase,0))
 # A quiet slower fundamental carries the late decay, not a fixed 185 Hz tone.
 result.append((f*2**(.35/1200),weights[0]*.08,min(6,taus[0]*2.2),4,0))
 result.append((0,.009,.0045,0,1))
 scale=15000/sum(abs(m[1]) for m in result)
 out=[]
 for hz,a,tau,phase,noise in result:
  amp=round(abs(a)*scale) if hz<20000 else 0
  inc=round(hz*2**32/FS) if hz<20000 else 0
  loss=min(65535,max(1,round((1-math.exp(-1/(FS*tau)))*2**24)))
  out.append((inc,amp,loss,phase,noise))
 assert len(out)==48 and sum(m[1] for m in out)<=15048
 return out
def generate():
 words=[]
 for p in range(2):
  for n in range(128):
   for inc,amp,loss,phase,noise in modes(p,n)+[(0,0,1,0,0)]*16:
    words.append(f'{(noise<<74)|(inc<<42)|(amp<<26)|(loss<<10)|phase:019x}')
 (ROOT/'rtl/rom/piano_v3_modes.mem').write_text('\n'.join(words)+'\n',encoding='ascii',newline='\n')
 (ROOT/'rtl/rom/rock_v2_shaper.mem').write_text('\n'.join(f'{v:04x}' for v in shaper())+'\n',encoding='ascii',newline='\n')
 print('Generated 16384 words; 48 active modal slots per voice; no PCM.')
if __name__=='__main__':generate()
