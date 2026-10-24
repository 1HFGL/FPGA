"""Bounded device-rejection/retry checks, with a transaction-level USB device."""
import hashlib,json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'build/touch_driver_20261024/host_faults';out.mkdir(parents=True,exist_ok=True)
sources=[root/p for p in ('rtl/usb/touch_usb_host.v','rtl/usb/touch_usb_control.v','verification/tb/control/tb_touch_usb_host.v')]
names=['normal','wrong_vid','zero_descriptor_length','bulk_endpoint','wrong_feature_count',
       'set_config_stall','persistent_nak_deadline','control_errors','poll_error_budget','poll_stall']
results=[]
for fault,name in enumerate(names):
    image=out/(name+'.vvp')
    cmd=['D:/iverilog/bin/iverilog.exe','-g2001','-s','tb_touch_usb_host',
         f'-Ptb_touch_usb_host.FAULT={fault}','-o',str(image),*map(str,sources)]
    subprocess.run(cmd,cwd=root,check=True,capture_output=True)
    result=subprocess.run(['D:/iverilog/bin/vvp.exe','-n',str(image)],cwd=root,capture_output=True,timeout=60)
    (out/(name+'.log')).write_bytes(result.stdout+result.stderr)
    body=result.stdout.decode()
    assert result.returncode==0 and 'PASS tb_touch_usb_host' in body and 'FAIL' not in body,body
    results.append({'case':name,'status':'PASS','result':body.splitlines()[0]})
    print(body.splitlines()[0],flush=True)
(out/'summary.json').write_text(json.dumps({'status':'PASS','cases':results,'inputs':{
    str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[Path(__file__)]}},indent=2)+'\n',encoding='utf-8')
