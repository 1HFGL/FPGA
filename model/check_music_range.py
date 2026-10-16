"""Static C3..C6 modal/ratio audit. Does not measure acoustic quality or nonlinear aliasing."""
import json,math
from check_music_pipe import load_config,ROOT

def check():
 table,_=load_config()
 ratio=[int(x,16) for x in (ROOT/'rtl/rom/pitch_bend_1025.mem').read_text().split()]
 assert len(ratio)==1025 and all(0<=x<2**17 for x in ratio)
 reports=[]
 for preset in (0,1):
  max_error=0.;max_hz=0.;min_modes=48;max_modes=0
  for note in range(48,85):
   m=table[preset,note];f=440*2**((note-69)/12)
   base=int(m[0,0])*48000/2**32
   max_error=max(max_error,abs(1200*math.log2(base/f)))
   audible=[row for row in m if row[1]>0 and row[4]==0]
   assert audible and m[0,1]>0
   min_modes=min(min_modes,len(audible));max_modes=max(max_modes,len(audible))
   # Upper global bend plus the maximum initial guitar pluck tension.
   r=(ratio[1024]*(65536+(512 if preset==0 else 0)))//65536
   for inc,amp,loss,phase,noise in audible:
    hz=((int(inc)*r)//65536)*48000/2**32;max_hz=max(max_hz,hz)
    assert hz<24000,(preset,note,hz)
   assert sum(int(row[1]) for row in m)<=15048
  assert max_error<.001
  reports.append(dict(preset=preset,notes=37,fundamental_max_error_cents=max_error,
      max_modal_hz_with_upper_bend=max_hz,nonzero_tonal_modes_min=min_modes,nonzero_tonal_modes_max=max_modes))
 result=dict(scope='ROM/modal bounds, not nonlinear aliasing or acoustic judgement',sample_rate=48000,midi_range=[48,84],presets=reports)
 out=ROOT/'build/regression/music/range_audit.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2))
 print('PASS range audit: 74 preset/note combinations C3..C6; packed ROM, base tuning, upper-bend modal Nyquist bounds')
 print(json.dumps(reports,indent=2))
if __name__=='__main__':check()
