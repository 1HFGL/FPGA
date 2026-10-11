# 在 ModelSim Transcript 中输入 source {本文件完整路径}。
# 使用脚本所在目录定位仓库，兼容从任意当前目录打开。
if {[info script] eq ""} { error "Run this script with source, not do." }
set timbre_script_path [info script]
if {[file pathtype $timbre_script_path] ne "absolute"} {
    set timbre_script_path [file join [pwd] $timbre_script_path]
}
set timbre_root [file dirname [file dirname $timbre_script_path]]
cd $timbre_root
catch {quit -sim}
file mkdir results/logs results/waves
set timbre_library results/timbre_work
if {![file exists $timbre_library/_info]} { vlib $timbre_library }
vlog -vlog01compat -pedanticerrors -work $timbre_library \
    rtl/phase_acc.v rtl/wave_lut.v rtl/wave_lut_timbre.v \
    rtl/adsr_env.v rtl/sample_gain.v rtl/voice_timbre_adsr.v \
    rtl/note_phase_lut.v rtl/sample_mixer4.v rtl/voice_bank_adsr.v \
    sim/tb_timbre_bank.v
vsim -voptargs=+acc -onfinish stop -lib $timbre_library \
    -l results/logs/tb_timbre_bank_gui.log \
    -wlf results/waves/tb_timbre_bank_gui.wlf tb_timbre_bank \
    +TIMBRE_TRACE_SHORT=results/logs/timbre_bank_gui_short_trace.txt \
    +TIMBRE_TRACE_BOUNDARY=results/logs/timbre_bank_gui_boundary_trace.txt \
    +TIMBRE_TRACE_ZERO=results/logs/timbre_bank_gui_zero_trace.txt
if {![batch_mode]} { view wave }
add wave -group control sim:/tb_timbre_bank/default_case/clk \
    sim:/tb_timbre_bank/default_case/rst_n \
    sim:/tb_timbre_bank/default_case/request \
    sim:/tb_timbre_bank/default_case/gates \
    sim:/tb_timbre_bank/default_case/triggers
# 输入音色可随时改变，已采纳音色只在接受新音符/重触发时更新。
add wave -group timbre -radix binary sim:/tb_timbre_bank/default_case/timbres \
    sim:/tb_timbre_bank/default_case/observed_timbre
add wave -group envelope -radix unsigned -format Analog-Step -height 70 \
    {sim:/tb_timbre_bank/default_case/dut/g_voice[0]/u_voice/env_level} \
    {sim:/tb_timbre_bank/default_case/dut/g_voice[1]/u_voice/env_level} \
    {sim:/tb_timbre_bank/default_case/dut/g_voice[2]/u_voice/env_level} \
    {sim:/tb_timbre_bank/default_case/dut/g_voice[3]/u_voice/env_level}
add wave -group output -radix decimal -format Analog-Step -height 120 \
    sim:/tb_timbre_bank/default_case/sample
add wave -group output sim:/tb_timbre_bank/default_case/valid \
    sim:/tb_timbre_bank/default_case/active \
    sim:/tb_timbre_bank/default_case/released \
    sim:/tb_timbre_bank/default_case/clipped
run -all
if {![batch_mode]} { wave zoom full }
foreach timbre_case {default_case boundary_case zero_case} {
    if {[examine -radix unsigned sim:/tb_timbre_bank/$timbre_case/done] ne "1"} {
        error "Timbre checks did not complete: $timbre_case"
    }
}
