"""Prove the implementation checker rejects USB pin/voltage/timing report faults.

Uses copies under build/; never changes source constraints or the real report.
Run only after the complete formal HDMI implementation check passes.
"""
import hashlib,json,re,shutil,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
base=root/'build/hdmi';out=root/'build/touch_driver_20261024/implementation_faults'
out.mkdir(parents=True,exist_ok=True)
checker=root/'verification/scripts/check_hdmi_implementation.py'
assert json.loads((base/'implementation_check.json').read_text(encoding='utf-8'))['status']=='PASS_CURRENT_CONSTRAINTS_ONLY'
for name in ('build_inputs.txt','build.log','timing.txt','piano_hdmi.rpt.txt','piano_hdmi_tr_content.html','artifact.txt'):
    shutil.copyfile(base/name,out/name)
report=(base/'piano_hdmi.rpt.txt').read_text(encoding='utf-8-sig')
timing=(base/'timing.txt').read_text(encoding='utf-8-sig')
line=next(x for x in report.splitlines() if x.startswith('usb_touch_dp '))
cells=line.split('|')
results=[]
for name,index,value in [('ball',2,'M15/4'),('bank',2,'H13/5'),('direction',4,'input'),
                         ('standard',7,'LVCMOS18'),('bias',9,'UP'),('voltage',17,'1.8')]:
    changed=cells.copy();changed[index]=' '+value+' '
    body=report.replace(line,'|'.join(changed),1)
    (out/'piano_hdmi.rpt.txt').write_text(body,encoding='utf-8')
    result=subprocess.run([sys.executable,str(checker),'--directory',str(out)],cwd=root,capture_output=True)
    summary=json.loads((out/'implementation_check.json').read_text(encoding='utf-8'))
    assert result.returncode and any('USB pin direction/bank/bias mismatch' in e or 'Pin missing/moved' in e for e in summary['errors']),name
    results.append({'case':name,'rejected':summary['errors']})
(out/'piano_hdmi.rpt.txt').write_text(report,encoding='utf-8')
for name,body in [('usb_clock_missing',timing.replace('usb_clk Setup 0.000 0','usb_unknown Setup 0.000 0',1)),
                  ('inactive_constraint',re.sub(r'(?m)^(TC_\w+) Actived ',r'\1 Inactive ',timing,count=1))]:
    assert body!=timing,name
    (out/'timing.txt').write_text(body,encoding='utf-8')
    result=subprocess.run([sys.executable,str(checker),'--directory',str(out)],cwd=root,capture_output=True)
    summary=json.loads((out/'implementation_check.json').read_text(encoding='utf-8'))
    assert result.returncode and any('Clock summary failed' in e or 'active constraints' in e for e in summary['errors']),name
    results.append({'case':name,'rejected':summary['errors']})
(out/'summary.json').write_text(json.dumps({'status':'PASS','cases':results,
    'checker_sha256':hashlib.sha256(checker.read_bytes()).hexdigest(),
    'real_report_sha256':hashlib.sha256((base/'piano_hdmi.rpt.txt').read_bytes()).hexdigest()},indent=2)+'\n',encoding='utf-8')
print('PASS USB implementation negative checks:',len(results))
