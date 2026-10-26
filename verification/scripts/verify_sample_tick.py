"""Exact sample-pulse timing, baseline/independent accumulator and fault control."""
from pathlib import Path
import argparse,hashlib,json,subprocess,shutil
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('--bin',default='C:/Library/modelsim/win64')
p.add_argument('--negative',action='store_true')
a=p.parse_args();tag='negative' if a.negative else 'positive'
out=ROOT/'build/regression/sample_tick'/tag;out.mkdir(parents=True,exist_ok=True)
dut=ROOT/'rtl/audio/sample_tick.v';baseline=ROOT/'verification/data/timing_followup/sample_tick_baseline.v'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
assert sha(baseline)=='78bc8ce92d35bc4439b5805efffc4e663fe868bfd974418d37500b61af9a30c7', 'Frozen reference changed'
ref=out/'sample_tick_reference.v'
ref.write_text(baseline.read_text(encoding='utf-8-sig').replace('module sample_tick #','module sample_tick_reference #',1),encoding='utf-8')
chosen=dut
if a.negative:
    s=dut.read_text(encoding='utf-8-sig');before='(PHASE_THRESHOLD-HALF_EDGE_RATE_HZ)'
    assert s.count(before)==1
    chosen=out/'sample_tick_mutated.v';chosen.write_text(s.replace(before,'(PHASE_THRESHOLD-HALF_EDGE_RATE_HZ+1)'),encoding='utf-8')
tb=ROOT/'verification/tb/audio/tb_tick_prediction.v'
snap=out/'testbench.v';shutil.copy2(tb,snap)
driver=out/'driver.py';shutil.copy2(Path(__file__),driver)
sources=[chosen,ref,snap]
manifest={'negative':a.negative,'source_sha256':{str(f):sha(f) for f in sources},
 'dut_sha256':sha(dut),'baseline_sha256':sha(baseline),'testbench_sha256':sha(tb),'driver_sha256':sha(driver)}
(out/'inputs.json').write_text(json.dumps(manifest,indent=2)+'\n')
lib=out.relative_to(ROOT).as_posix()+'/work';bin=Path(a.bin)
macro=out/'run.do';macro.write_text('onerror {quit -code 1 -f}\nonbreak {quit -code 1 -f}\nrun -all\nquit -code 0 -f\n')
for tool,args in [('vlib',[lib]),('vlog',['-vlog01compat','-pedanticerrors','-work',lib,*map(str,sources)]),
 ('vsim',['-c','-lib',lib,'tb_tick_prediction','-l',str(out/'transcript.log'),'-wlf',str(out/'waves.wlf'),'-do','do {'+macro.as_posix()+'}'])]:
    with (out/(tool+'.log')).open('w',encoding='utf-8') as f:
        r=subprocess.run([str(bin/(tool+'.exe')),*args],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,timeout=600)
    assert r.returncode==0,(tool,out)
body=(out/'vsim.log').read_text(encoding='utf-8',errors='replace')
assert '** Error:' not in body and '** Fatal:' not in body
if a.negative:assert 'FAIL tick ' in body and 'PASS tb_tick_prediction' not in body
else:assert 'PASS tb_tick_prediction' in body and 'FAIL ' not in body
result={'status':'EXPECTED_FAULT_REJECTED' if a.negative else 'PASS',
 'markers':[s for s in body.splitlines() if 'PASS ' in s or 'FAIL ' in s],
 'input_manifest_sha256':sha(out/'inputs.json'),'log_sha256':sha(out/'vsim.log')}
(out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
