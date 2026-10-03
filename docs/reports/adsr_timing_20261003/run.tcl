if {[catch {
    open_project {C:/Users/Nanji/AppData/Local/Temp/codex_adsr_timing_20261003/gowin_verify/a_dds_check.gprj}
    set_option -include_path {C:/Users/Nanji/Documents/GitHub/FPGA}
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS: 50 MHz synthesis and place-and-route completed.}
exit 0
