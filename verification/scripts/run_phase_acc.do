# Use: source {path/to/FPGA/verification/scripts/run_phase_acc.do}
# Tcl source supplies info script; ModelSim do does not reliably do so.
if {[info script] eq ""} { error "Use source to run this script, not do." }
set a_script_dir [file dirname [info script]]
source [file join $a_script_dir a_common.tcl]
a_run [file dirname [file dirname $a_script_dir]] tb_phase_acc
