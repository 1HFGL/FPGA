if {![file isdirectory work]} {
    vlib work
}

vlog -sv ../rtl/input_sync_debounce.v ../rtl/touch_or_key_if.v ../rtl/pressure_if.v ../rtl/event_encoder.v ../rtl/voice_allocator.v ../rtl/reset_sync.v ../rtl/voice_test_pattern.v ../rtl/interaction_top.v ../rtl/board_top.v ../rtl/board_test_top.v ../tb/tb_input_sync_debounce.sv ../tb/tb_pressure_if.sv ../tb/tb_event_encoder.sv ../tb/tb_voice_allocator.sv ../tb/tb_interaction_top.sv ../tb/tb_voice_test_pattern.sv