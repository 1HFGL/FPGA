"""Current integration tests. Strict Verilog-2001; logs and generated data only in build/."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('tops', nargs='+')
p.add_argument('--bin', default='C:/Library/modelsim/win64')
p.add_argument('--gowin-simlib', default='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v')
p.add_argument('--legacy', action='store_true', help='Run an unchanged historical contract test with explicit compatibility parameters')
p.add_argument('--mutation', choices=['None','Preset','Release','Wave','Env'], default='None')
a = p.parse_args()
OUT = ROOT / 'build/regression/final'
OUT.mkdir(parents=True, exist_ok=True)
sources = sorted(ROOT.glob('rtl/**/*.v'))
for top in a.tops:
    candidates = list((ROOT / 'verification/tb').rglob(top + '.v'))
    if len(candidates) != 1:
        raise SystemExit('Expected one current test: ' + top)
    tb = candidates[0]
    tag=top+('_legacy' if a.legacy else '')+('_'+a.mutation if a.mutation!='None' else '')
    lib = (OUT / (tag + '_work')).relative_to(ROOT).as_posix()
    test_sources=list(sources)
    if a.mutation!='None':
        options={
            'Preset':('tb_final_modal_adapter','rtl/synth/voice_bank_modal_adapter.v','.voice_instrument(~voice_guitar)','.voice_instrument(voice_guitar)','FAIL modal golden mismatch'),
            'Release':('tb_final_modal_adapter','rtl/synth/voice_bank_modal_adapter.v','(!busy && !sample_valid && raw_release[v])','raw_release[v]','FAIL stale release'),
            'Wave':('tb_final_wave_envelope','rtl/display/display_wave_envelope.v','sample_data>first_sample','sample_data<first_sample','FAIL pair peak lost'),
            'Env':('tb_final_env_alignment','rtl/synth/instrument_env.v','next_level=attack_first_level;','next_level=17\'d0;','FAIL env current preset')}
        required,path,before,after,failure=options[a.mutation]
        if top!=required or a.legacy:raise SystemExit('Mutation requires '+required)
        original=ROOT/path
        body=original.read_text(encoding='utf-8')
        if body.count(before)!=1:raise SystemExit('Mutation target ambiguous')
        mutant=OUT/(tag+'_mutation.v')
        mutant.write_text(body.replace(before,after),encoding='utf-8')
        test_sources=[mutant if f==original else f for f in sources]
    def run(exe, args, log):
        with log.open('w', encoding='utf-8') as f:
            result = subprocess.run([str(Path(a.bin) / (exe + '.exe')), *args],
                                    cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
        body = log.read_text(errors='replace')
        if result.returncode or re.search(r'\bFAIL\b|\*\* (Error|Fatal):', body):
            print(body[-5000:]); raise SystemExit('Failed: ' + str(log))
        return body
    support = [ROOT/'verification/tb/integration/performance_adc_model.v'] if top in ('tb_final_performance','tb_performance_adc') else []
    sim_top=top
    if a.legacy:
        instances={'tb_final_performance':['dut'],'tb_performance_adc':['dut'],'tb_performance_latency':['dut'],
            'tb_review_dual_system':['dut'],'tb_hdmi_audio_isolation':['dut','baseline']}
        if top not in instances:raise SystemExit('No compatibility override defined for '+top)
        sim_top='legacy_'+top
        wrapper=OUT/(sim_top+'.v')
        wrapper.write_text('module '+sim_top+';\n'+top+' original();\n'+
            '\n'.join('defparam original.'+inst+('.ENABLE_BRIGHTNESS=0;' if top=='tb_final_performance' else '.USE_MODAL=0;') for inst in instances[top])+'\nendmodule\n')
        support.append(wrapper)
    vendor=Path(a.gowin_simlib) if top in (
        'tb_final_hdmi_isolation','tb_hdmi_phy','tb_final_hdmi_reset','tb_hdmi_audio_isolation') else None
    inputs = [*test_sources, *support, tb, Path(__file__).resolve(), *ROOT.glob('rtl/rom/*.mem')]+([vendor] if vendor else [])
    (OUT / (tag + '_inputs.json')).write_text(json.dumps({
        'flags': '-vlog01compat -pedanticerrors',
        'mode':'explicit legacy compatibility' if a.legacy else 'current integration',
        'mutation':a.mutation,
        'sha256': {(str(f.relative_to(ROOT)) if f.is_relative_to(ROOT) else str(f)): hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}}, indent=2))
    if not (ROOT / lib / '_info').exists():
        run('vlib', [lib], OUT / (tag + '_vlib.log'))
    run('vlog', ['-vlog01compat', '-pedanticerrors', '-work', lib, *map(str, [*test_sources,*support]), str(tb)],
        OUT / (tag + '_compile.log'))
    if vendor:
        run('vlog',['-work',lib,str(vendor)],OUT/(tag+'_vendor_compile.log'))
    macro = OUT / (tag + '.do')
    macro.write_text('onerror {quit -code 1 -f}\nonbreak {quit -code 1 -f}\nrun -all\nquit -code 0 -f\n')
    if a.mutation!='None':
        command=[str(Path(a.bin)/'vsim.exe'),'-c','-lib',lib,sim_top,'-l',str(OUT/(tag+'.log')),
            '-wlf',str(OUT/(tag+'.wlf')),'-do','do {'+macro.as_posix()+'}']
        with (OUT/(tag+'_console.log')).open('w') as stream:
            subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
        body=(OUT/(tag+'_console.log')).read_text(errors='replace')
        if failure not in body or 'PASS '+top in body:raise SystemExit('Fault not rejected by intended checker: '+tag)
        print('PASS negative '+a.mutation+': '+failure,flush=True)
        continue
    body = run('vsim', ['-c', '-lib', lib, sim_top, '-l', str(OUT / (tag + '.log')),
        '-wlf', str(OUT / (tag + '.wlf')), '-do', 'do {' + macro.as_posix() + '}'],
        OUT / (tag + '_console.log'))
    lines = [line for line in body.splitlines() if 'PASS ' + top in line]
    if not lines: raise SystemExit('Missing completion marker: ' + top)
    print('\n'.join(lines), flush=True)
