# 独立正弦UART项目；不覆盖其他工程的试听位流。
set project_dir [file dirname [file normalize [info script]]]
if {[catch {
    cd $project_dir
    file mkdir [file join $project_dir impl]
    file copy -force [file join $project_dir process_config.json] \
        [file join $project_dir impl uart_basic_process_config.json]
    open_project [file join $project_dir uart_basic.gprj]
    set_option -top_module instrument_uart_top
    set_option -output_base_name instrument_uart
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS UART synthesis and place-and-route completed; no programming.}
exit 0
