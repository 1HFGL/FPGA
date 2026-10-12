set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir knob_verified.gprj]
set_option -top_module board_knob_top
run all
puts {KNOB_FIX_BUILD_DONE}
exit 0
