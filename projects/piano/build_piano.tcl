# 当前钢琴主工程；旧演示版本仅保留在Git历史。
# Gowin在open_project时读取impl中的process配置；先恢复受版本控制的副本，
# 才能让清空旧impl后的构建与现有构建采用同一套选项。
set project_dir [file normalize [file dirname [info script]]]
cd $project_dir
source [file join $project_dir .. check_modal_rom.tcl]
set process_config [file join $project_dir process_config.json]
set impl_dir [file join $project_dir impl]
if {![file isfile $process_config]} {
    error "Missing controlled process configuration: $process_config"
}
file mkdir $impl_dir
file copy -force $process_config [file join $impl_dir uart_piano_process_config.json]
if {[catch {
    open_project [file join $project_dir uart_piano.gprj]
    set_option -top_module piano_performance_top
    set_option -output_base_name piano_performance
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS piano synthesis and place-and-route completed; no programming.}
exit 0
