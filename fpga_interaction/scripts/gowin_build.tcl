set project_dir [file dirname [file dirname [file normalize [info script]]]]
open_project [file join $project_dir tang_mega_60k_interaction.gprj]
run all
exit 0
