# instrument_demo_top：只构建，不操作板卡。四个模式共享工程，必须串行运行。
set project_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $project_dir ../../..]]
if {[catch {
    cd $project_dir
    file mkdir [file join $project_dir impl]
    file copy -force [file join $project_dir process_config.json] \
        [file join $project_dir impl fpga_project_process_config.json]
    open_project [file join $project_dir fpga_project.gprj]
    set_option -top_module instrument_demo_top
    set_option -output_base_name instrument_demo
    set_option -include_path $repo_dir
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS instrument_demo synthesis and place-and-route completed; no programming.}
exit 0
