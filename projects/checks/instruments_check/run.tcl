# Run with gw_sh; this builds only and never programs hardware.
# Paths follow this script so teammates can keep their own checkout location.
set script_file [info script]
if {[file pathtype $script_file] eq "relative"} {
    set script_file [file join [pwd] $script_file]
}
set check_dir [file dirname [file normalize $script_file]]
set repo_dir [file normalize [file join $check_dir ../../..]]
if {[catch {
    cd $check_dir
    # Start from saved settings; the generated impl directory is ignored by Git.
    file mkdir [file join $check_dir impl]
    file copy -force [file join $check_dir process_config.json]         [file join $check_dir impl instruments_check_process_config.json]
    open_project [file join $check_dir instruments_check.gprj]
    set_option -top_module voice_bank_instruments_timing_top
    set_option -output_base_name instruments_check
    set_option -include_path $repo_dir
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS: registered four-voice dual-instrument 50 MHz synthesis and place-and-route completed.}
exit 0
