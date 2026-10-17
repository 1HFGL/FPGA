# Use Tcl source, not ModelSim do.
if {[info script] eq ""} { error "Use source to run this script, not do." }
set a_script_dir [file dirname [info script]]
source [file join $a_script_dir a_common.tcl]
a_run [file dirname [file dirname $a_script_dir]] tb_voice_adsr
