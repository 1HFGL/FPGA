# 由build.ps1 -Mode Legacy生成隔离GPRJ，不构建projects/legacy历史工程。
set project_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $project_dir ../..]]
if {[catch {
    if {![info exists env(FPGA_LEGACY_PROJECT)]} {
        error {Run projects/uart_basic/build.ps1 -Mode Legacy first.}
    }
    set legacy_project [file normalize $env(FPGA_LEGACY_PROJECT)]
    set legacy_dir [file dirname $legacy_project]
    cd $legacy_dir
    file mkdir [file join $legacy_dir impl]
    file copy -force [file join $repo_dir projects examples adsr process_config.json] \
        [file join $legacy_dir impl legacy_check_process_config.json]
    open_project $legacy_project
    set_option -top_module instrument_adsr_top
    set_option -output_base_name instrument_adsr_check
    set_option -include_path $repo_dir
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS isolated ADSR compatibility build; no programming.}
exit 0
