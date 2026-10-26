"""Current integration tests. Strict Verilog-2001; logs and generated data only in build/."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('tops', nargs='+')
p.add_argument('--bin', default='C:/Library/modelsim/win64')
p.add_argument('--gowin-simlib', default='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v')
p.add_argument('--out', default='build/regression/final')
p.add_argument('--timeout', type=int, default=1800)
p.add_argument('--functional-rom', action='store_true', help='Qualified simulation-only ROM; never a synthesis input')
p.add_argument('--usb-fault', type=int, choices=range(10), help='Existing USB host fault parameter, without editing the TB')
p.add_argument('--plusarg', action='append', default=[], help='Simulation plusarg, e.g. COUNT=2031')
p.add_argument('--voices16', action='store_true', help='Explicit historical 16-voice formal-top contract')
p.add_argument('--legacy-brightness', action='store_true', help='Explicit original one-pole/R955 compatibility; never current formal HDMI evidence')
p.add_argument('--enhanced-brightness', action='store_true', help='Derived R958 touch integration harness; preserve the original R955 TB byte-for-byte')
p.add_argument('--dry', action='store_true', help='Disable all effects explicitly for unchanged dry contract tests')
p.add_argument('--reverb-only', action='store_true', help='Disable chorus and delay for unchanged room-only contract tests')
p.add_argument('--legacy', action='store_true', help='Run an unchanged historical contract test with explicit compatibility parameters')
p.add_argument('--mutation', choices=['None','Preset','Release','Wave','Env','TouchRelease','BleCancel','GuideAdvance','HdmiRecovery','FifoExchange','EnvSlot','ConfigCrc','PracticePause'], default='None')
a = p.parse_args()
if sum((a.dry,a.legacy,a.reverb_only))>1:raise SystemExit('Use separate dry, legacy and reverb-only runs')
if a.enhanced_brightness and (a.legacy_brightness or a.dry or a.legacy or a.reverb_only or a.voices16):
    raise SystemExit('Enhanced brightness requires the current 32-voice/effects configuration')
OUT = ROOT / a.out
OUT.mkdir(parents=True, exist_ok=True)
sources = sorted(ROOT.glob('rtl/**/*.v'))
for top in a.tops:
    candidates = list((ROOT / 'verification/tb').rglob(top + '.v'))
    if len(candidates) != 1:
        raise SystemExit('Expected one current test: ' + top)
    tb = candidates[0]
    if top=='tb_dual16_hdmi':(ROOT/'build/regression/dual16').mkdir(parents=True,exist_ok=True)
    if top=='tb_brightness_hdmi':(ROOT/'build/brightness_response').mkdir(parents=True,exist_ok=True)
    if top=='tb_poly32_hdmi':(ROOT/'build/regression/poly32').mkdir(parents=True,exist_ok=True)
    tag=top+('_voices16' if a.voices16 else '')+('_dry' if a.dry else '')+('_legacy' if a.legacy else '')+('_reverb_only' if a.reverb_only else '')+('_'+a.mutation if a.mutation!='None' else '')+('_fault'+str(a.usb_fault) if a.usb_fault is not None else '')
    tag += '_legacy_brightness' if a.legacy_brightness else ''
    tag += '_enhanced_brightness' if a.enhanced_brightness else ''
    lib = (OUT / (tag + '_work')).relative_to(ROOT).as_posix()
    test_sources=list(sources)
    rom_inputs=[]
    if a.functional_rom or top=='tb_merge32_rom_equivalence':
        if a.mutation!='None':raise SystemExit('Use separate ROM qualification and mutation runs')
        from functional_dual_rom import generate
        model,data=generate(ROOT,OUT/tag)
        physical=ROOT/'rtl/rom/modal_coeff_rom_dual.v'
        test_sources=[model if f==physical else f for f in test_sources]
        rom_inputs=data+[physical,ROOT/'verification/scripts/functional_dual_rom.py',ROOT/'rtl/rom/piano_v3_modes.mem']
        if top=='tb_merge32_rom_equivalence':
            reference=OUT/'modal_coeff_rom_dual_vendor.v'
            reference.write_bytes(physical.read_bytes().replace(b'module modal_coeff_rom_dual(',b'module modal_coeff_rom_dual_vendor('))
            test_sources.append(reference)
        else:
            certificate=json.loads((ROOT/'verification/evidence/usb_touch/rom_qualification.json').read_text(encoding='utf-8'))
            if certificate['status']!='PASS':raise SystemExit('ROM model is not qualified')
            hashes={k.replace('\\','/'):v for k,v in certificate['inputs'].items()}
            for f in rom_inputs[2:]:
                key=f.relative_to(ROOT).as_posix()
                if hashes.get(key)!=hashlib.sha256(f.read_bytes()).hexdigest():raise SystemExit('ROM qualification stale: '+key)
    if top in ('tb_poly32_core','tb_dual16_core','tb_dual16_snapshot'):
        # Compare against the exact pre-optimization algorithm, never against a
        # second instance of the rewritten pipeline.
        original=subprocess.check_output(['git','show','f314bc066a428b7f43b19c0c8fa1586e6a98dc24:rtl/synth/voice_bank_music_pipe.v'],cwd=ROOT)
        frozen=OUT/'voice_bank_music_serial_reference.v'
        frozen.write_bytes(original.replace(b'module voice_bank_music_pipe #(',b'module voice_bank_music_serial_reference #('))
        test_sources.append(frozen)
    if top=='tb_event_encoder_equivalence':
        original=subprocess.check_output(['git','show','36b81ab2983ef04823784c95a345e4383c2b2724:rtl/control/event_encoder.v'],cwd=ROOT)
        frozen=OUT/'event_encoder_reference.v'
        frozen.write_bytes(original.replace(b'module event_encoder #(',b'module event_encoder_reference #('))
        test_sources.append(frozen)
    if top=='tb_uart_fifo_equivalence':
        original=subprocess.check_output(['git','show','e2355c4ea4bf055f641944d50fbce87360e57f1c:rtl/control/uart_fifo.v'],cwd=ROOT)
        frozen=OUT/'uart_fifo_reference.v'
        frozen.write_bytes(original.replace(b'module uart_fifo #',b'module uart_fifo_reference #'))
        test_sources.append(frozen)
    if top=='tb_env_bank_equivalence':
        original=subprocess.check_output(['git','show','e2355c4ea4bf055f641944d50fbce87360e57f1c:rtl/synth/instrument_env.v'],cwd=ROOT)
        frozen=OUT/'instrument_env_reference.v'
        frozen.write_bytes(original.replace(b'module instrument_env #(',b'module instrument_env_reference #('))
        test_sources.append(frozen)
    if top == 'tb_touch_mux_equivalence':
        # This differential TB needs the frozen pre-sharing tracker as well as
        # the current DUT. Never compare two copies of today's implementation.
        original = subprocess.check_output([
            'git', 'show',
            'e2355c4ea4bf055f641944d50fbce87360e57f1c:rtl/control/touch_contact_tracker.v',
        ], cwd=ROOT)
        frozen = OUT / 'touch_contact_tracker_reference.v'
        frozen.write_bytes(original.replace(
            b'module touch_contact_tracker #(',
            b'module touch_contact_tracker_reference #(',
        ))
        test_sources.append(frozen)
    if a.mutation!='None':
        options={
            'ConfigCrc':('tb_performance_store','rtl/control/performance_store.v',"else if(arg1!=(crc^32'hffffffff))", "else if(1'b0)",'FAIL command'),
            'PracticePause':('tb_practice_boundaries','rtl/control/timed_practice_guide.v',
                'wire advancing=running && !(command_valid && command_kind==4);','wire advancing=running;','pause/count-in boundary consumes tick'),
            'EnvSlot':('tb_env_bank_equivalence','rtl/synth/instrument_env_bank16.v','step_slot<=slot;',"step_slot<=4'd0;",'FAIL bank equivalence'),
            'FifoExchange':('tb_uart_fifo_equivalence','rtl/control/uart_fifo.v',
                'wire pop=out_valid && out_ready;',
                'wire pop=out_valid && out_ready && !in_valid;','FAIL fifo differential'),
            'Preset':('tb_final_modal_adapter','rtl/synth/voice_bank_modal_adapter.v','.voice_instrument(~voice_guitar)','.voice_instrument(voice_guitar)','FAIL modal golden mismatch'),
            'Release':('tb_final_modal_adapter','rtl/synth/voice_bank_modal_adapter.v','(!busy && !sample_valid && raw_release[v])','raw_release[v]','FAIL stale release'),
            'Wave':('tb_final_wave_envelope','rtl/display/display_wave_envelope.v','sample_data>first_sample','sample_data<first_sample','FAIL pair peak lost'),
            'Env':('tb_final_env_alignment','rtl/synth/instrument_env.v','next_level=attack_first_level;','next_level=17\'d0;','FAIL env current preset'),
            'TouchRelease':('tb_touch_contact_tracker','rtl/control/touch_contact_tracker.v','if(held[index])begin',"if(1'b0)begin",'FAIL missing touch event'),
            'BleCancel':('tb_ble_event_arbiter','rtl/control/uart_event_arbiter.v',
                "assign allocator_cancel_mask=ENABLE_BLE ? 9'h180 : 8'h80;",
                "assign allocator_cancel_mask=ENABLE_BLE ? 9'h100 : 8'h80;",'FAIL BLE cancel boundary/mask'),
            'GuideAdvance':('tb_practice_guide','rtl/control/practice_guide.v','played_note==target_note',"1'b1",'FAIL guide wrong note advanced'),
            'HdmiRecovery':('tb_review_hdmi_reset_recovery','rtl/display/dvi_tx_gowin.v',
                'assign tmds_data_p=positive[2:0];assign tmds_data_n=negative[2:0];',
                "integer mutation_resets=0; always @(negedge rst_n) mutation_resets=mutation_resets+1;\n"+
                "assign tmds_data_p=positive[2:0] ^ ((mutation_resets>=2)?3'b100:3'b000);\n"+
                "assign tmds_data_n=negative[2:0] ^ ((mutation_resets>=2)?3'b100:3'b000);",'FAIL HDMI reset word alignment epoch=1')}
        required,path,before,after,failure=options[a.mutation]
        if top!=required or a.legacy:raise SystemExit('Mutation requires '+required)
        original=ROOT/path
        body=original.read_text(encoding='utf-8')
        # Match executable fragments across harmless formatting changes. Keep the
        # exactly-one guard so a stale or ambiguous target never produces a pass.
        fragment_tokens = re.findall(
            r'[A-Za-z_$][A-Za-z0-9_$]*|\d[\d_]*|<<<|>>>|===|!==|==|!=|<=|>=|&&|\|\||<<|>>|[^\s]',
            before,
        )
        fragment_pattern = r'\s*'.join(re.escape(token) for token in fragment_tokens)
        body, replacements = re.subn(fragment_pattern, lambda match: after, body)
        if replacements != 1:
            raise SystemExit('Mutation target ambiguous: expected one fragment, found ' + str(replacements))
        mutant=OUT/(tag+'_mutation.v')
        mutant.write_text(body,encoding='utf-8')
        test_sources=[mutant if f==original else f for f in test_sources]
    def run(exe, args, log):
        with log.open('w', encoding='utf-8') as f:
            result = subprocess.run([str(Path(a.bin) / (exe + '.exe')), *args],
                                    cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, timeout=a.timeout)
        body = log.read_text(errors='replace')
        if result.returncode or re.search(r'\bFAIL\b|\*\* (Error|Fatal):', body):
            print(body[-5000:]); raise SystemExit('Failed: ' + str(log))
        return body
    support = [ROOT/'verification/tb/integration/performance_adc_model.v'] if top in ('tb_final_performance','tb_performance_adc','tb_performance_octaves') else []
    if top in ('tb_slider_guide_hdmi','tb_slider_controls_filtered','tb_controls_meter_hdmi','tb_brightness_hdmi'):
        support.append(ROOT/'verification/tb/integration/tb_slider_controls.v')
    if top=='tb_review_knob_latency':support.append(ROOT/'verification/tb/review/ads1115_timed_model.v')
    sim_top=top
    if a.legacy:
        instances={'tb_final_performance':['dut'],'tb_performance_adc':['dut'],'tb_performance_latency':['dut'],
            'tb_review_dual_system':['dut'],'tb_hdmi_audio_isolation':['dut','baseline']}
        if top not in instances:raise SystemExit('No compatibility override defined for '+top)
        sim_top='legacy_'+top
        wrapper=OUT/(sim_top+'.v')
        wrapper.write_text('module '+sim_top+';\n'+top+' original();\n'+
            '\n'.join('defparam original.'+inst+('.ENABLE_BRIGHTNESS=0;\ndefparam original.'+inst+'.ENABLE_OCTAVE_KEY=0;' if top=='tb_final_performance' else '.USE_MODAL=0;')+''.join('\ndefparam original.'+inst+'.'+param+'=0;' for param in ('ENABLE_CHORUS','ENABLE_DELAY','ENABLE_REVERB')) for inst in instances[top])+'\nendmodule\n')
        support.append(wrapper)
    if a.dry:
        if a.legacy:raise SystemExit('Use separate dry and legacy runs')
        instances={'tb_touch_hdmi_audio':['dut'],'tb_hdmi_octaves':['dut','baseline'],
            'tb_performance_octaves':['dut'],'tb_final_hdmi_isolation':['dut','baseline']}
        if top not in instances:raise SystemExit('No dry compatibility override for '+top)
        sim_top='dry_'+top
        wrapper=OUT/(sim_top+'.v')
        wrapper.write_text('module '+sim_top+';\n'+top+' original();\n'+
            '\n'.join('defparam original.'+inst+'.'+param+'=0;' for inst in instances[top] for param in ('ENABLE_CHORUS','ENABLE_DELAY','ENABLE_REVERB'))+'\nendmodule\n')
        support.append(wrapper)
    if a.reverb_only:
        instances={'tb_reverb_hdmi':['dut','baseline']}
        if top not in instances:raise SystemExit('No reverb-only override for '+top)
        sim_top='reverb_only_'+top
        wrapper=OUT/(sim_top+'.v')
        wrapper.write_text('module '+sim_top+';\n'+top+' original();\n'+
            '\n'.join('defparam original.'+inst+'.'+param+'=0;' for inst in instances[top] for param in ('ENABLE_CHORUS','ENABLE_DELAY'))+'\nendmodule\n')
        support.append(wrapper)
    if a.voices16:
        instances={'tb_effects_hdmi':['dut','baseline'],'tb_reverb_hdmi':['dut','baseline'],
            'tb_touch_hdmi_audio':['dut'],'tb_final_hdmi_isolation':['dut','baseline'],
            'tb_hdmi_octaves':['dut','baseline'],'tb_performance_octaves':['dut'],
            'tb_final_performance':['dut'],'tb_review_uart_capacity_top':['dut']}
        if top not in instances:raise SystemExit('No historical voice override for '+top)
        parent=sim_top
        sim_top='voices16_'+parent
        wrapper=OUT/(sim_top+'.v')
        prefix='original.'+('original.' if parent!=top else '')
        wrapper.write_text('module '+sim_top+';\n'+parent+' original();\n'+
            '\n'.join('defparam '+prefix+inst+'.VOICES=16;' for inst in instances[top])+'\nendmodule\n')
        support.append(wrapper)
    if a.legacy_brightness:
        if top not in ('tb_controls_meter_hdmi','tb_dual16_hdmi') or sim_top!=top:
            raise SystemExit('Legacy brightness requires an unchanged R955 HDMI contract test')
        sim_top='legacy_brightness_'+top
        wrapper=OUT/(sim_top+'.v')
        wrapper.write_text('module '+sim_top+';\n'+top+' original();\n'
                           'defparam original.dut.ENHANCED_BRIGHTNESS=0;\nendmodule\n')
        support.append(wrapper)
    harness_inputs=[]
    if a.enhanced_brightness:
        if top!='tb_touch32_audio' or sim_top!=top or a.mutation!='None':
            raise SystemExit('Enhanced brightness harness requires tb_touch32_audio without mutation')
        # Reuse the full six-touch/four-source stimulus without changing the
        # teammate's R955 test. Only select the new filter and require R958;
        # every voice, source-isolation, reset and deadline assertion remains.
        original_tb=tb
        body=tb.read_text(encoding='utf-8')
        sim_top='enhanced_brightness_'+top
        replacements=(
            ('module tb_touch32_audio;', 'module '+sim_top+';'),
            ('.ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),',
             '.ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),.ENHANCED_BRIGHTNESS(1),'),
            ('cycle-issued!=955','cycle-issued!=958'),
            ('FAIL touch changed R955','FAIL touch changed R958'),
            ('nonzero audio R955','nonzero audio R958'))
        for before,after in replacements:
            if body.count(before)!=1:raise SystemExit('Touch R958 harness anchor changed: '+before)
            body=body.replace(before,after)
        tb=OUT/(sim_top+'.v')
        tb.write_text(body,encoding='utf-8')
        harness_inputs.append(original_tb)
    vendor=Path(a.gowin_simlib) if top in (
        'tb_brightness_hdmi','tb_controls_meter_hdmi',
        'tb_review_hdmi_reset_recovery','tb_slider_guide_hdmi','tb_dual16_snapshot','tb_dual16_uart','tb_dual16_core','tb_dual16_rom','tb_dual16_hdmi','tb_poly32_hdmi','tb_effects_hdmi','tb_reverb_hdmi','tb_touch_hdmi_audio','tb_final_hdmi_isolation','tb_hdmi_octaves','tb_hdmi_phy','tb_final_hdmi_reset','tb_hdmi_audio_isolation') else None
    if 'hdmi' in top or top in ('tb_merge32_rom_equivalence','tb_three_key_chords','tb_usb_system_recovery','tb_usb_dual_clock','tb_usb_dual_wire'):vendor=Path(a.gowin_simlib)
    inputs = [*test_sources, *support, tb, *harness_inputs, Path(__file__).resolve(), *ROOT.glob('rtl/rom/*.mem'), *rom_inputs]+([vendor] if vendor else [])
    (OUT / (tag + '_inputs.json')).write_text(json.dumps({
        'flags': '-vlog01compat -pedanticerrors',
        'voices16':a.voices16,
        'legacy_brightness':a.legacy_brightness,
        'enhanced_brightness':a.enhanced_brightness,
        'mode':'explicit dry compatibility' if a.dry else ('explicit legacy compatibility' if a.legacy else ('explicit reverb-only compatibility' if a.reverb_only else 'current integration')),
        'mutation':a.mutation,
        'functional_rom':a.functional_rom, 'usb_fault':a.usb_fault, 'plusargs':a.plusarg,
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
    sim_args=[]
    if a.usb_fault is not None:
        if top!='tb_touch_usb_host':raise SystemExit('--usb-fault requires tb_touch_usb_host')
        sim_args.append('-gFAULT='+str(a.usb_fault))
    sim_args.extend('+'+x for x in a.plusarg)
    body = run('vsim', ['-c', '-lib', lib, sim_top, *sim_args, '-l', str(OUT / (tag + '.log')),
        '-wlf', str(OUT / (tag + '.wlf')), '-do', 'do {' + macro.as_posix() + '}'],
        OUT / (tag + '_console.log'))
    marker='PASS: tb_voice_allocator_32' if top=='tb_voice_allocator' else 'PASS '+top
    lines = [line for line in body.splitlines() if marker in line or ('PASS: '+top) in line]
    if not lines: raise SystemExit('Missing completion marker: ' + top)
    print('\n'.join(lines), flush=True)
