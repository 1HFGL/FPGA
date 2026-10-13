# 仅综合通用显示核心。屏幕型号未定，故无CST/板级SDC，不运行布局布线或生成下载文件。
set project_dir [file dirname [file normalize [info script]]]
if {[catch {
    cd $project_dir
    file mkdir [file join $project_dir impl]
    file copy -force [file join $project_dir process_config.json] \
        [file join $project_dir impl display_rgb_process_config.json]
    open_project [file join $project_dir display_rgb.gprj]
    set_option -top_module instrument_display
    set_option -output_base_name display_rgb
    run syn
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS display RTL synthesis only; no board timing or hardware claim.}
exit 0
