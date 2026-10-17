"""Strict Verilog-2001 regression of the integrated piano/rock engine. No hardware I/O."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,math
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('tops',nargs='*',default=['tb_music_protocol','tb_music_pipe','tb_music_uart16','tb_music_display_isolation','tb_music_controls','tb_music_local_controls','tb_music_recovery'])
p.add_argument('--bin',default='D:/modelsim1/win64')
p.add_argument('--negative',action='store_true')
a=p.parse_args()
OUT=ROOT/'build/regression/music';OUT.mkdir(parents=True,exist_ok=True)
sources=sorted(ROOT.glob('rtl/**/*.v'))
# Reconstruct the legacy transfer analytically; no second active synthesis core.
legacy=OUT/'rock_v2_legacy_shaper.mem'
legacy.write_text('\n'.join(f'{round(12000*math.tanh(i*32/900)):04x}' for i in range(1024))+'\n',encoding='ascii')
def run(exe,args,log,expected_failure=False):
    with log.open('w') as f:
        ret=subprocess.run([str(Path(a.bin)/(exe+'.exe')),*args],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    body=log.read_text(errors='replace')
    if not expected_failure and (ret.returncode or re.search(r'\bFAIL\b|\*\* (Error|Fatal):',body)):
        print(body[-6000:]);raise SystemExit(f'{exe} failed: {log}')
    return body
for top in a.tops:
    if top not in ['tb_music_protocol','tb_music_pipe','tb_music_uart16','tb_music_display_isolation','tb_music_controls','tb_music_local_controls','tb_music_recovery']:
        raise SystemExit('Unknown test '+top)
    if a.negative and top!='tb_music_uart16':raise SystemExit('Negative control is for the UART serial scoreboard')
    tag=top+('_negative' if a.negative else '')
    lib=(OUT/(tag+'_work')).relative_to(ROOT).as_posix()
    if not (ROOT/lib/'_info').exists():run('vlib',[str(lib)],OUT/(tag+'_vlib.log'))
    tb=ROOT/f'verification/tb/music/{top}.v'
    inputs=[*sources,tb,Path(__file__).resolve(),*ROOT.glob('rtl/rom/*.mem')]+([legacy] if top=='tb_music_pipe' else [])
    (OUT/(tag+'_inputs.json')).write_text(json.dumps({
        'flags':'-vlog01compat -pedanticerrors',
        'sha256':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}},indent=2))
    run('vlog',['-vlog01compat','-pedanticerrors','-work',str(lib),
                *(['+define+NEGATIVE_CONTROL'] if a.negative else []),
                *map(str,sources),str(tb)],OUT/(tag+'_compile.log'))
    macro=OUT/(tag+'.do')
    macro.write_text('onerror {quit -code 1 -f}\nonbreak {quit -code 1 -f}\nrun -all\nquit -code 0 -f\n')
    body=run('vsim',['-c','-lib',str(lib),top,'+CAPTURE='+(OUT/(tag+'.csv')).as_posix(),
        '-l',str(OUT/(tag+'.log')),'-wlf',str(OUT/(tag+'.wlf')),'-do',f'do {{{macro.as_posix()}}}'],
        OUT/(tag+'_console.log'),a.negative)
    if a.negative:
        if 'FAIL: serial mismatch' not in body or 'PASS tb_music_uart16' in body:
            raise SystemExit('Injected serial corruption was not rejected by expected checker')
        print('PASS negative control: UART serial corruption rejected',flush=True)
    else:
        if f'PASS {top}' not in body:raise SystemExit('Missing completion marker: '+top)
        print('\n'.join(line for line in body.splitlines() if 'PASS '+top in line),flush=True)
