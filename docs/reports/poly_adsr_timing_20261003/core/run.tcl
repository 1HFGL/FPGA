# Standalone core verification only; no hardware programming.
if {[catch {
    open_project {C:/Users/Nanji/AppData/Local/Temp/codex_poly_adsr_timing_20261003/gowin_verify/poly_adsr_check.gprj}
    set_option -top_module voice_bank_adsr
    set_option -output_base_name poly_adsr_check
    set_option -include_path {C:/Users/Nanji/AppData/Local/Temp/codex_poly_adsr_timing_20261003}
    run all
} result]} {
    puts stderr $result
    exit 1
}
puts {PASS: four-voice 50 MHz synthesis and place-and-route completed.}
exit 0
