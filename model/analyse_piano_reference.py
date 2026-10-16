from pathlib import Path
import json, numpy as np
ROOT=Path(__file__).resolve().parents[1]
def analyse(note):
 x=np.load(ROOT/f'build/piano_reference/C{note//12-1}.npy');fs=44100;f=440*2**((note-69)/12)
 rms=np.sqrt(np.mean(x[:len(x)//441*441].reshape(-1,441)**2,axis=1))
 onset=np.flatnonzero(rms>rms.max()*.035)[0]/100
 size=262144; hz=np.fft.rfftfreq(size,1/fs)
 seg=x[int((onset+.12)*fs):int((onset+1.12)*fs)]
 spec=abs(np.fft.rfft(seg*np.hanning(len(seg)),size))
 centers=[]
 for h in range(1,25):
  lo=f*h*.985;hi=min(19800,f*h*(1.018+.00025*h*h))
  ix=np.flatnonzero((hz>=lo)&(hz<=hi))
  centers.append(float(hz[ix[np.argmax(spec[ix])]]) if len(ix) else f*h)
 hs=np.arange(1,9);y=(np.array(centers[:8])/hs)**2
 # Frequency stiffening estimate, independently fit intercept and slope.
 slope,inter=np.polyfit(hs**2,y,1);B=float(np.clip(slope/inter,1e-6,.003))
 f0=float(np.sqrt(max(inter,1)*(1+B)))
 times=np.array([.08,.16,.30,.50,.80,1.2,1.8,2.5,3.5])
 powers=[]
 for t in times:
  seg=x[int((onset+t)*fs):int((onset+t+.16)*fs)];win=np.hanning(len(seg))
  s=abs(np.fft.rfft(seg*win,65536))**2;freq=np.fft.rfftfreq(65536,1/fs)
  row=[]
  for h,c in enumerate(centers,1):
   width=max(15,c*.004)
   mask=(freq>c-width)&(freq<c+width)
   row.append(float(np.sqrt(s[mask].sum())))
  powers.append(row)
 powers=np.array(powers);amp=np.sqrt(np.mean(powers[:3]**2,axis=0));amp/=amp.max()
 strong=np.flatnonzero(amp[:8]>.012)+1
 if len(strong)<2:strong=np.array([1,2])
 slope,inter=np.polyfit(strong**2,(np.array(centers)[strong-1]/strong)**2,1,w=np.sqrt(amp[strong-1]))
 B=float(np.clip(slope/inter,1e-6,.006));f0=float(np.sqrt(max(inter,1)*(1+B)))
 taus=[]
 for k in range(24):
  y=np.log(np.maximum(powers[:,k],1e-9));valid=(powers[:,k]>powers[:,k].max()*.04)&(times<=2.5)
  slope=np.polyfit(times[valid],y[valid],1)[0] if valid.sum()>2 else -5
  taus.append(float(np.clip(-1/min(slope,-.15),.09,5)))
 out=dict(note=note,onset_seconds=float(onset),measured_f0=f0,stiffness=B,weights=amp.tolist(),tau=taus,partial_centers=centers,times=times.tolist(),partial_magnitudes=powers.tolist())
 print(note,'f0',round(f0,2),'B',round(B,6),'weights',np.round(amp[:12],3),'taus',np.round(taus[:12],2),flush=True)
 return out
if __name__=='__main__':
 out=[analyse(n) for n in [48,60,72,84]]
 (ROOT/'model/piano_reference_fit.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
