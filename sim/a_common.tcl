# Called through Tcl source, not ModelSim do, so info script is defined.
proc a_run {root top} {
    set root [file join [pwd] $root]
    foreach path {rtl/phase_acc.v rtl/wave_lut.v rtl/voice_dds.v rtl/rom/sine_1024.mem} {
        if {![file isfile [file join $root $path]]} { error "Missing file: $path" }
    }
    catch {quit -sim}
    cd $root
    set lib [file join $root results a_work]
    file mkdir [file dirname $lib]
    if {![file exists [file join $lib _info]]} { vlib $lib }
    vlog -sv -work $lib [file join $root rtl phase_acc.v] [file join $root rtl wave_lut.v] [file join $root rtl voice_dds.v] [file join $root sim ${top}.v]
    file mkdir [file join $root results waves]
    vsim -lib $lib -voptargs=+acc -wlf [file join $root results waves ${top}.wlf] $top
    view wave
    if {$top eq "tb_voice_dds"} {
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
    if {$top eq "tb_voice_dds"} { wave zoom range 0ns 10000000ns } else { wave zoom full }
}
