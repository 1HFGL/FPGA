set project_dir [file normalize [file dirname [info script]]]
cd $project_dir
source [file join $project_dir .. check_modal_rom.tcl]
# Gowin每个工程只读取一个CST/SDC；生成合并文件，公共引脚只维护piano.cst一处。
set generated [file normalize ../../build/hdmi]
file mkdir $generated
foreach ext {cst sdc} {
    set output [open [file join $generated piano_hdmi.$ext] w]
    foreach part {piano hdmi ble usb} {
        set input [open ../../boards/tang_mega_60k_31004/$part.$ext r]
        puts $output [read $input]
        close $input
    }
    if {$ext eq "cst"} {
        set input [open ../../boards/tang_mega_60k_31004/hdmi_reset_placement.cst r]
        puts $output [read $input]
        close $input
    }
    close $output
}
file mkdir impl
file copy -force process_config.json impl/piano_hdmi_process_config.json
if {[llength $argv] && [lindex $argv 0] eq "prepare"} {
    puts {PASS HDMI combined constraints prepared; open piano_hdmi.gprj in Gowin.}
    exit 0
}
if {[catch {
    open_project piano_hdmi.gprj
    set_option -top_module piano_hdmi_top
    set_option -output_base_name piano_hdmi
    # 保留工具实际采纳的选项，便于核对process配置与实现报告。
    saveto -all_options [file join $generated effective_options.tcl]
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS HDMI synthesis and PNR execution; inspect timing/constraints before hardware use.}
exit 0
