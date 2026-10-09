# Build this board audition only; never downloads to hardware.
# First run creates impl/instruments_board_process_config.json so the GUI
# opened afterward retains the correct top/module options.
set script_file [info script]
if {[file pathtype $script_file] eq "relative"} {
    set script_file [file join [pwd] $script_file]
}
set project_dir [file dirname $script_file]
set repo_dir [file dirname [file dirname $project_dir]]
if {[catch {
    file mkdir [file join $project_dir impl]
    file copy -force [file join $project_dir process_config.json] \
        [file join $project_dir impl instruments_board_process_config.json]
    open_project [file join $project_dir instruments_board.gprj]
    set_option -top_module instrument_presets_top
    set_option -output_base_name instruments_board
    set_option -include_path $repo_dir
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS: two-instrument 31004 board audition synthesis and place-and-route completed. No programming performed.}
exit 0
