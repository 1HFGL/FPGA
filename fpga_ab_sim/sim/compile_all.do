if {![file isdirectory work]} {
    vlib work
}
vlog -sv ../../fpga_interaction/rtl/input_sync_debounce.v ../../fpga_interaction/rtl/touch_or_key_if.v ../../fpga_interaction/rtl/pressure_if.v ../../fpga_interaction/rtl/adc_knob_if.v ../../fpga_interaction/rtl/event_encoder.v ../../fpga_interaction/rtl/voice_allocator.v ../../fpga_interaction/rtl/voice_test_pattern.v ../../fpga_interaction/rtl/interaction_top.v ../../fpga_a/rtl/phase_inc_calc.v ../../fpga_a/rtl/wave_lut.v ../../fpga_a/rtl/adsr_envelope.v ../../fpga_a/rtl/voice_gain.v ../../fpga_a/rtl/poly_mixer_saturator.v ../../fpga_a/rtl/synth_engine.v ../../fpga_b/rtl/sample_tick_gen.v ../../fpga_b/rtl/i2s_tx.v ../rtl/audio_system_top.v ../tb/tb_c_ab_system.sv ../tb/tb_c_ab_system_32.sv
vlog -sv ../tb/tb_retrigger_audio.sv
vlog -sv ../tb/tb_poly_mixer.sv
vlog -sv ../tb/tb_audio_pipeline.sv
