if {![file isdirectory work]} {
    vlib work
}

vlog -sv ../rtl/input_sync_debounce.v ../rtl/touch_or_key_if.v ../rtl/pressure_if.v ../rtl/adc_knob_if.v ../rtl/i2c_master.v ../rtl/ads1115_if.v ../rtl/ads1115_knob_if.v ../rtl/event_encoder.v ../rtl/voice_allocator.v ../rtl/reset_sync.v ../rtl/voice_test_pattern.v ../rtl/interaction_top.v ../rtl/board_top.v ../rtl/board_test_top.v ../rtl/board_knob_top.v ../tb/tb_input_sync_debounce.sv ../tb/tb_pressure_if.sv ../tb/tb_adc_knob_if.sv ../tb/tb_event_encoder.sv ../tb/tb_voice_allocator.sv ../tb/tb_interaction_top.sv ../tb/tb_voice_test_pattern.sv ../tb/tb_keyboard_extended.sv ../tb/ads1115_model.sv ../tb/tb_ads1115_if.sv ../tb/tb_ads1115_knob_if.sv ../tb/tb_ads1115_faults.sv ../tb/tb_ads1115_mapping.sv

vlog -sv ../tb/tb_voice_control.sv

vlog -sv ../tb/tb_key_events.sv

vlog -sv ../tb/tb_input_fault_cleanup.sv
