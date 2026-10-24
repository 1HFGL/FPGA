# 单次高云任务。由sweep_pnr.ps1的调度器在独立目录调用，不修改正式impl。
# 选项依据本机SUG1220-2.1E，第36-42页；不使用未经支持的seed参数。
# 布局0..4，布线0..2，时钟布线顺序0/1；所有I/O/时序/物理约束保持。
set project_dir [file normalize [file dirname [info script]]]
cd $project_dir
source [file join $project_dir .. check_modal_rom.tcl]
if {[llength $argv] != 4} {
    puts stderr {Usage: gw_sh pnr_trial.tcl <syn|pnr|options> <place 0..4> <route 0..2> <clock-order 0|1>}
    exit 2
}
lassign $argv stage place route clock_order
if {$stage ni {syn pnr options} || $place ni {0 1 2 3 4} ||
    $route ni {0 1 2} || $clock_order ni {0 1}} {
    puts stderr {Invalid flow or implementation option}
    exit 2
}
if {[catch {
    file mkdir impl
    file copy -force process_config.json impl/piano_hdmi_process_config.json
    open_project piano_hdmi.gprj
    set_option -top_module piano_hdmi_top
    set_option -output_base_name piano_hdmi
    set_option -place_option $place
    set_option -route_option $route
    set_option -clock_route_order $clock_order
    if {$stage eq "pnr"} {
        if {![file isfile impl/gwsynthesis/piano_hdmi.vg]} {
            error {Missing common synthesis netlist; refusing implicit resynthesis}
        }
        # 仅复制gwsynthesis目录仍会隐式综合；隔离GPRJ必须预先切换为网表输入。
        # set_file_enable/add_file会自动保存工程，故本阶段只检查，不修改输入。
        set input [open piano_hdmi.gprj r]
        set project_xml [read $input]
        close $input
        set netlists 0
        foreach entry [regexp -all -inline {<File\s[^>]*>} $project_xml] {
            if {![regexp {enable="0"} $entry]} {
                if {[regexp {type="file\.(verilog|vhdl)"} $entry]} {
                    error {Active RTL in PNR project; refusing implicit resynthesis}
                }
                if {[regexp {type="file\.netlist"} $entry]} {
                    if {![regexp {path="impl/gwsynthesis/piano_hdmi.vg"} $entry]} {
                        error {Unexpected PNR netlist input}
                    }
                    incr netlists
                }
            }
        }
        if {$netlists != 1} {error {Expected exactly one common PNR netlist}}
    }
    saveto -all_options effective_options.tcl
    if {$stage ne "options"} {run $stage}
} result]} {
    puts stderr $result
    exit 1
}
puts "PASS sweep worker: stage=$stage place=$place route=$route clock_order=$clock_order"
exit 0
