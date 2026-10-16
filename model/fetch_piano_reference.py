from pathlib import Path
import urllib.request,aifc,numpy as np,hashlib,json
out=Path(__file__).resolve().parents[1]/'build/piano_reference';out.mkdir(parents=True,exist_ok=True)
report=[]
for note in [48,60,72,84]:
 name=f'Piano.mf.C{note//12-1}.aiff';p=out/name
 url='https://theremin.music.uiowa.edu/sound%20files/MIS/Piano_Other/piano/'+name
 if not p.exists():
  with urllib.request.urlopen(url,timeout=45) as r:p.write_bytes(r.read())
 with aifc.open(str(p),'rb') as f:
  fs=f.getframerate();ch=f.getnchannels();w=f.getsampwidth();data=f.readframes(f.getnframes())
 assert w==2
 x=np.frombuffer(data,dtype='>i2').astype(float).reshape(-1,ch).mean(axis=1)/32768
 entry=dict(note=note,file=name,url=url,fs=fs,channels=ch,seconds=len(x)/fs,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
 report.append(entry);print(entry,flush=True)
 np.save(out/f'C{note//12-1}.npy',x)
(out/'sources.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
