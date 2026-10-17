# 在 ModelSim Transcript 中使用 source {本文件完整路径}。
# 脚本根据自己的位置定位仓库，不依赖打开软件时的当前目录。
if {[info script] eq ""} { error "Run this script with source, not do." }
# 老版 ModelSim 的 file normalize 在部分 Windows 目录会改写路径；
# 保留 source 传入的原始目录，只补全相对路径。
set poly_script_path [info script]
if {[file pathtype $poly_script_path] ne "absolute"} {
    set poly_script_path [file join [pwd] $poly_script_path]
}
set poly_root [file dirname [file dirname [file dirname $poly_script_path]]]
cd $poly_root
catch {quit -sim}
file mkdir build/regression/logs build/regression/waves
set poly_library build/regression/poly_adsr_work
if {![file exists $poly_library/_info]} { vlib $poly_library }
vlog -vlog01compat -pedanticerrors -work $poly_library \
    rtl/synth/phase_acc.v rtl/synth/wave_lut.v rtl/synth/voice_dds.v \
    rtl/synth/adsr_env.v rtl/synth/sample_gain.v rtl/synth/voice_adsr.v \
    rtl/control/note_phase_lut.v rtl/synth/sample_mixer4.v rtl/synth/voice_bank_adsr.v \
    rtl/synth/wave_lut_timbre.v rtl/synth/voice_timbre_adsr.v \
    verification/tb/synth/tb_voice_bank_adsr.v
vsim -voptargs=+acc -onfinish stop -lib $poly_library \
    -l build/regression/logs/tb_voice_bank_adsr_gui.log \
    -wlf build/regression/waves/tb_voice_bank_adsr_gui.wlf tb_voice_bank_adsr \
    +POLY_TRACE_DEFAULT=build/regression/logs/poly_adsr_default_trace.txt \
    +POLY_TRACE_BOUNDARY=build/regression/logs/poly_adsr_boundary_trace.txt
if {![batch_mode]} { view wave }
add wave -group control sim:/tb_voice_bank_adsr/default_case/clk \
    sim:/tb_voice_bank_adsr/default_case/rst_n \
    sim:/tb_voice_bank_adsr/default_case/request \
    sim:/tb_voice_bank_adsr/default_case/gates \
    sim:/tb_voice_bank_adsr/default_case/triggers
add wave -group envelope -radix unsigned -format Analog-Step -height 70 \
    {sim:/tb_voice_bank_adsr/default_case/dut/g_voice[0]/u_voice/env_level} \
    {sim:/tb_voice_bank_adsr/default_case/dut/g_voice[1]/u_voice/env_level} \
    {sim:/tb_voice_bank_adsr/default_case/dut/g_voice[2]/u_voice/env_level} \
    {sim:/tb_voice_bank_adsr/default_case/dut/g_voice[3]/u_voice/env_level}
add wave -group output -radix decimal -format Analog-Step -height 120 \
    sim:/tb_voice_bank_adsr/default_case/sample
add wave -group output sim:/tb_voice_bank_adsr/default_case/valid \
    sim:/tb_voice_bank_adsr/default_case/active \
    sim:/tb_voice_bank_adsr/default_case/released \
    sim:/tb_voice_bank_adsr/default_case/clipped
run -all
if {![batch_mode]} { wave zoom full }
if {[examine -radix unsigned sim:/tb_voice_bank_adsr/default_case/done] ne "1" ||
    [examine -radix unsigned sim:/tb_voice_bank_adsr/boundary_case/done] ne "1"} {
    error "Poly ADSR checks did not complete."
}
