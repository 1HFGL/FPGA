# Called through Tcl source, not ModelSim do, so info script is defined.
proc a_run {root top} {
    set root [file join [pwd] $root]
    foreach path {rtl/synth/phase_acc.v rtl/synth/wave_lut.v rtl/synth/voice_dds.v rtl/rom/sine_1024.mem} {
        if {![file isfile [file join $root $path]]} { error "Missing file: $path" }
    }
    catch {quit -sim}
    cd $root
    set lib build/regression/a_work
    file mkdir [file dirname $lib]
    if {![file exists [file join $lib _info]]} { vlib $lib }
    set sources {}
    foreach name {phase_acc wave_lut voice_dds} {
        lappend sources [file join $root rtl synth ${name}.v]
    }
    if {$top in {tb_adsr_env tb_sample_gain tb_voice_adsr}} {
        foreach name {adsr_env sample_gain voice_adsr} {
            lappend sources [file join $root rtl synth ${name}.v]
        }
    }
    lappend sources [file join $root verification tb synth ${top}.v]
    vlog -vlog01compat -pedanticerrors -work $lib {*}$sources
    file mkdir [file join $root build regression waves]
    vsim -lib $lib -voptargs=+acc -onfinish stop -wlf [file join $root build regression waves ${top}.wlf] $top
    if {![batch_mode]} { view wave }
    if {$top eq "tb_voice_adsr"} {
        add wave sim:/$top/clk sim:/$top/rst sim:/$top/sample_tick
        add wave sim:/$top/gate sim:/$top/retrigger sim:/$top/voice_active
        add wave -radix unsigned -format Analog-Step -height 140 sim:/$top/env_level
        add wave -radix unsigned sim:/$top/dut/env_state
        add wave -radix decimal -format Analog-Step -height 180 sim:/$top/sample
        add wave sim:/$top/sample_valid
    } elseif {$top eq "tb_adsr_env"} {
        add wave sim:/$top/clk sim:/$top/rst sim:/$top/sample_tick
        add wave sim:/$top/gate sim:/$top/retrigger sim:/$top/active
        add wave -radix unsigned sim:/$top/state
        add wave -radix unsigned -format Analog-Step -height 180 sim:/$top/env_level
    } elseif {$top eq "tb_voice_dds"} {
        add wave sim:/$top/clk sim:/$top/rst sim:/$top/sample_tick
        add wave -radix unsigned sim:/$top/phase_inc
        add wave -radix hexadecimal sim:/$top/dut/phase
        add wave -radix unsigned sim:/$top/dut/wave_addr
        add wave -radix decimal -format Analog-Step -height 180 sim:/$top/sample
        add wave sim:/$top/sample_valid
    } elseif {$top eq "tb_wave_lut"} {
        add wave sim:/$top/clk sim:/$top/rst sim:/$top/read_en
        add wave -radix unsigned sim:/$top/addr
        add wave -radix decimal -format Analog-Step -height 180 sim:/$top/sample
        add wave sim:/$top/sample_valid
    } else {
        add wave sim:/$top/clk sim:/$top/rst sim:/$top/sample_tick
        add wave -radix hexadecimal sim:/$top/phase_inc sim:/$top/phase
        add wave -radix unsigned sim:/$top/wave_addr
    }
    run -all
    if {$top eq "tb_voice_dds"} {
        wave zoom range 0ns 10000000ns
    } elseif {$top eq "tb_adsr_env"} {
        wave zoom range 0ns 350000ns
    } else { wave zoom full }
}
