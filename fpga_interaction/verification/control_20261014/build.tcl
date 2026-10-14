set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir control_verified.gprj]
set_option -top_module control_audio_verify_top
run all
puts {CONTROL_BUILD_DONE}
exit 0
