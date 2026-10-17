# 在 ModelSim Transcript 中输入 source {本文件完整路径}。
# 使用脚本所在目录定位仓库，兼容从任意当前目录打开。
if {[info script] eq ""} { error "Run this script with source, not do." }
set instrument_script_path [info script]
if {[file pathtype $instrument_script_path] ne "absolute"} {
    set instrument_script_path [file join [pwd] $instrument_script_path]
}
set instrument_root [file dirname [file dirname [file dirname $instrument_script_path]]]
cd $instrument_root
catch {quit -sim}
file mkdir build/regression/logs build/regression/waves
set instrument_library build/regression/instrument_work
if {![file exists $instrument_library/_info]} { vlib $instrument_library }
vlog -vlog01compat -pedanticerrors -work $instrument_library \
    rtl/synth/phase_acc.v rtl/synth/wave_lut.v rtl/synth/instrument_wave.v \
    rtl/synth/instrument_env.v rtl/synth/sample_gain.v rtl/synth/voice_instrument.v \
    rtl/control/note_phase_lut.v rtl/synth/sample_mixer4.v rtl/synth/voice_bank_instruments.v \
    verification/tb/synth/tb_instrument_bank.v
vsim -voptargs=+acc -onfinish stop -lib $instrument_library \
    -l build/regression/logs/tb_instrument_bank_gui.log \
    -wlf build/regression/waves/tb_instrument_bank_gui.wlf tb_instrument_bank \
    +INSTRUMENT_TRACE_SHORT=build/regression/logs/instrument_bank_gui_short_trace.txt \
    +INSTRUMENT_TRACE_BOUNDARY=build/regression/logs/instrument_bank_gui_boundary_trace.txt \
    +INSTRUMENT_TRACE_ZERO=build/regression/logs/instrument_bank_gui_zero_trace.txt \
    +INSTRUMENT_TRACE_EXTREME=build/regression/logs/instrument_bank_gui_extreme_trace.txt
if {![batch_mode]} { view wave }
add wave -group control sim:/tb_instrument_bank/default_case/clk \
    sim:/tb_instrument_bank/default_case/rst_n \
    sim:/tb_instrument_bank/default_case/request \
    sim:/tb_instrument_bank/default_case/gates \
    sim:/tb_instrument_bank/default_case/triggers
# 输入音色可随时改变，已采纳音色只在接受新音符/重触发时更新。
add wave -group instrument -radix binary sim:/tb_instrument_bank/default_case/instruments \
    sim:/tb_instrument_bank/default_case/observed_instrument
add wave -group envelope -radix unsigned -format Analog-Step -height 70 \
    {sim:/tb_instrument_bank/default_case/dut/g_voice[0]/u_voice/env_level} \
    {sim:/tb_instrument_bank/default_case/dut/g_voice[1]/u_voice/env_level} \
    {sim:/tb_instrument_bank/default_case/dut/g_voice[2]/u_voice/env_level} \
    {sim:/tb_instrument_bank/default_case/dut/g_voice[3]/u_voice/env_level}
add wave -group brightness -radix unsigned -format Analog-Step -height 70 \
    {sim:/tb_instrument_bank/default_case/dut/g_voice[0]/u_voice/tone_level} \
    {sim:/tb_instrument_bank/default_case/dut/g_voice[1]/u_voice/tone_level}
add wave -group output -radix decimal -format Analog-Step -height 120 \
    sim:/tb_instrument_bank/default_case/sample
add wave -group output sim:/tb_instrument_bank/default_case/valid \
    sim:/tb_instrument_bank/default_case/active \
    sim:/tb_instrument_bank/default_case/released \
    sim:/tb_instrument_bank/default_case/clipped
run -all
if {![batch_mode]} { wave zoom full }
foreach instrument_case {default_case boundary_case zero_case extreme_case} {
    if {[examine -radix unsigned sim:/tb_instrument_bank/$instrument_case/done] ne "1"} {
        error "Instrument checks did not complete: $instrument_case"
    }
}
