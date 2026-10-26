"""Exact reset/video differential against a frozen Git source; no hardware access."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source-root', type=Path, default=ROOT)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--reference-revision', default='e2355c4ea4bf055f641944d50fbce87360e57f1c')
p.add_argument('--bin', type=Path, default=Path('C:/Library/modelsim/win64'))
p.add_argument('--vendor', type=Path, default=Path('D:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v'))
p.add_argument('--mutation', choices=('none','early_release'), default='none')
a = p.parse_args()
source, out = a.source_root.resolve(), a.out.resolve()
out.mkdir(parents=True, exist_ok=True)
rel = 'rtl/display/dvi_tx_gowin.v'
original = subprocess.check_output(['git','show',a.reference_revision+':'+rel], cwd=ROOT)
reference = out / 'dvi_tx_gowin_reference.v'
reference.write_bytes(original.replace(b'module dvi_tx_gowin(', b'module dvi_tx_gowin_reference('))
dut = source / rel
if a.mutation != 'none':
    body = dut.read_text(encoding='utf-8')
    body, count = re.subn(r"LUT2 #\(\.INIT\(4'b(?:0111|0011)\)\)", "LUT2 #(.INIT(4'b0101))", body)
    if count != 1:
        raise SystemExit('Expected one reset LUT for early-release mutation')
    # The implementation may tie unused I0 low. Reconnect the first stage so
    # this negative control specifically releases one cycle early, not never.
    body = body.replace(".I0(1'b0)", '.I0(serializer_release[0])')
    dut = out / 'dvi_early_release.v'
    dut.write_text(body, encoding='utf-8')
tb = ROOT / 'verification/tb/display/tb_serializer_reset_equivalence.v'
sources = [dut, source/'rtl/display/tmds_encoder.v', reference, tb]
lib = out / 'work'

def run(tool, arguments, name):
    log = out / name
    with log.open('w', encoding='utf-8') as f:
        result = subprocess.run([str(a.bin/(tool+'.exe')), *[x.as_posix() if isinstance(x,Path) else x for x in arguments]],
                                cwd=source, stdout=f, stderr=subprocess.STDOUT, timeout=180)
    return result.returncode, log.read_text(encoding='utf-8', errors='replace')

for tool, arguments, name in [
    ('vlib',[lib],'vlib.log'),
    ('vlog',['-vlog01compat','-pedanticerrors','-work',lib,*sources],'compile.log'),
    ('vlog',['-work',lib,a.vendor],'vendor.log')]:
    code, body = run(tool,arguments,name)
    if code or '** Error:' in body:
        raise SystemExit(body[-4000:])
macro = out/'run.do'
macro.write_text('onerror {quit -code 1 -f}\nonbreak {quit -code 1 -f}\nrun -all\nquit -code 0 -f\n')
code, body = run('vsim',['-c','-lib',lib,'tb_serializer_reset_equivalence','-wlf',out/'run.wlf','-do','do {'+macro.as_posix()+'}'],'simulation.log')
if a.mutation == 'none':
    ok = not code and not re.search(r'\bFAIL\b|\*\* (Error|Fatal):', body) and 'PASS tb_serializer_reset_equivalence' in body
else:
    ok = 'FAIL serializer reset equivalence' in body and 'PASS tb_serializer_reset_equivalence' not in body
# Exhaust the reachable state graph independently of either RTL implementation.
states = {0}
while True:
    reached = states | {0} | {((s&1)<<1)|1 for s in states}
    if reached == states:
        break
    states = reached
assert states == {0,1,3}
assert all((not ((s&1) and (s&2))) == (not (s&2)) for s in states)
summary = {'status':'PASS' if ok else 'FAIL','mutation':a.mutation,
           'reference_revision':a.reference_revision,'reference_sha256':hashlib.sha256(original).hexdigest(),
           'reachable_states':sorted(states),'state_proof':'00 -> 01 -> 11; asynchronous assertion returns 00',
           'limits':'Digital equivalence only; analog metastability and physical path timing require separate evidence.',
           'sha256':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources+[a.vendor,Path(__file__)]}}
counts = re.search(r'equivalence: (\d+) epochs, (\d+) exact', body)
if counts:
    summary.update(epochs=int(counts[1]), exact_checks=int(counts[2]))
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
if not ok:
    raise SystemExit(body[-4000:])
print('\n'.join(line.lstrip('# ') for line in body.splitlines() if 'PASS tb_' in line or 'FAIL serializer' in line))
if a.mutation != 'none':
    print('PASS early-release mutation rejected')
