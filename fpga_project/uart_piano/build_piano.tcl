# 独立钢琴感工程，旧正弦/普通/自动位流不覆盖。
# Gowin在open_project时读取impl中的process配置；先恢复受版本控制的副本，
# 才能让清空旧impl后的构建与现有构建采用同一套选项。
set project_dir [file normalize [file dirname [info script]]]
set process_config [file join $project_dir process_config.json]
set impl_dir [file join $project_dir impl]
if {![file isfile $process_config]} {
    error "Missing controlled process configuration: $process_config"
}
file mkdir $impl_dir
file copy -force $process_config [file join $impl_dir uart_piano_process_config.json]
open_project uart_piano.gprj
set_option -top_module instrument_uart_piano_top
set_option -output_base_name instrument_uart_piano
run all
