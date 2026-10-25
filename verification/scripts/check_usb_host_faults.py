"""Bounded device-rejection/retry checks, with a transaction-level USB device."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--modelsim-bin',type=Path,help='Use strict ModelSim instead of Icarus')
p.add_argument('--bin',type=Path,default=Path('D:/iverilog/bin'))
a=p.parse_args()
out=root/'build/touch_driver_20261024/host_faults';out.mkdir(parents=True,exist_ok=True)
sources=[root/p for p in ('rtl/usb/touch_usb_host.v','rtl/usb/touch_usb_control.v','verification/tb/control/tb_touch_usb_host.v')]
names=['normal','wrong_vid','zero_descriptor_length','bulk_endpoint','wrong_feature_count',
       'set_config_stall','persistent_nak_deadline','control_errors','poll_error_budget','poll_stall']
results=[]
for fault,name in enumerate(names):
    image=out/(name+'.vvp')
    if a.modelsim_bin:
        cmd=[sys.executable,str(root/'verification/scripts/run_final_tests.py'),'--bin',str(a.modelsim_bin),
             '--out','build/touch_driver_20261024/host_faults/modelsim','--usb-fault',str(fault),'tb_touch_usb_host']
    else:
        cmd=[str(a.bin/'iverilog.exe'),'-g2001','-s','tb_touch_usb_host',
             f'-Ptb_touch_usb_host.FAULT={fault}','-o',str(image),*map(str,sources)]
        subprocess.run(cmd,cwd=root,check=True,capture_output=True)
        cmd=[str(a.bin/'vvp.exe'),'-n',str(image)]
    result=subprocess.run(cmd,cwd=root,capture_output=True,timeout=180)
    (out/(name+'.log')).write_bytes(result.stdout+result.stderr)
    body=result.stdout.decode()
    assert result.returncode==0 and 'PASS tb_touch_usb_host' in body and 'FAIL' not in body,body
    results.append({'case':name,'status':'PASS','result':body.splitlines()[0]})
    print(body.splitlines()[0],flush=True)
(out/'summary.json').write_text(json.dumps({'status':'PASS','cases':results,
    'simulator':'ModelSim strict Verilog-2001' if a.modelsim_bin else 'Icarus -g2001','inputs':{
    str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[Path(__file__)]}},indent=2)+'\n',encoding='utf-8')
