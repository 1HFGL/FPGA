from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent
files=['control_audio_verify_top.v']
files+=['../../rtl/'+name+'.v' for name in ['input_sync_debounce','touch_or_key_if','pressure_if','adc_knob_if',
        'event_encoder','voice_allocator','reset_sync','voice_test_pattern','interaction_top']]
files+=['../../../fpga_a/rtl/'+name+'.v' for name in ['phase_inc_calc','wave_lut','adsr_envelope',
        'voice_gain','poly_mixer_saturator','synth_engine']]
files+=['../../../fpga_b/rtl/'+name+'.v' for name in ['sample_tick_gen','i2s_tx']]
files+=['../../../fpga_ab_sim/rtl/audio_system_top.v','../../gowin/tang_mega_60k_interaction.cst',
        '../../gowin/tang_mega_60k_interaction.sdc']
project=ET.Element('Project')
ET.SubElement(project,'Template').text='FPGA'
ET.SubElement(project,'Version').text='5'
ET.SubElement(project,'Device',name='GW5AT-60B',pn='GW5AT-LV60PG484AC1/I0').text='gw5at60b-002'
filelist=ET.SubElement(project,'FileList')
for filename in files:
    assert (ROOT/filename).is_file(),filename
    typ={'.v':'file.verilog','.cst':'file.cst','.sdc':'file.sdc'}[Path(filename).suffix]
    ET.SubElement(filelist,'File',path=filename,type=typ,enable='1')
ET.indent(project)
(ROOT/'control_verified.gprj').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE gowin-fpga-project>\n'+ET.tostring(project,encoding='unicode')+'\n',encoding='utf-8')
for relative,additions in {
    '../../sim/compile_all.do':['../tb/tb_voice_control.sv','../tb/tb_key_events.sv','../tb/tb_input_fault_cleanup.sv'],
    '../../../fpga_ab_sim/sim/compile_all.do':['../tb/tb_retrigger_audio.sv','../tb/tb_poly_mixer.sv','../tb/tb_audio_pipeline.sv']}.items():
    path=ROOT/relative
    text=path.read_text(encoding='utf-8-sig')
    for addition in additions:
        if addition not in text: text+='\nvlog -sv '+addition+'\n'
    path.write_text(text,encoding='utf-8')
print('Prepared relative-path Gowin verification project and compile scripts.')
