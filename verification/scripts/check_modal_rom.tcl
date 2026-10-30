# GUI/命令行共用的输入门槛：派生bank必须与原始参数逐字一致；不自动重写ROM。
set modal_root [file normalize [file join [file dirname [info script]] .. ..]]
set modal_source [file join $modal_root rtl rom piano_v3_modes.mem]
proc modal_read_words {path} {
    if {![file isfile $path]} {error "Missing modal ROM: $path; run model/pack_modal_rom.py --write"}
    set channel [open $path r]
    set body [read $channel]
    close $channel
    return [regexp -all -inline {\S+} [string tolower $body]]
}
set modal_words [modal_read_words $modal_source]
if {[llength $modal_words] != 16384} {error {Invalid canonical modal ROM size}}
for {set bank 0} {$bank < 3} {incr bank} {
    set packed [modal_read_words "$modal_source.bank$bank.mem"]
    if {[llength $packed] != 4096} {error "Invalid modal bank size: $bank"}
    for {set index 0} {$index < 4096} {incr index} {
        set original [expr {($index >> 4)*64 + $bank*16 + ($index & 15)}]
        if {[lindex $packed $index] ne [lindex $modal_words $original]} {
            error "Stale modal bank$bank at $index; run model/pack_modal_rom.py --write"
        }
    }
}
for {set note 0} {$note < 256} {incr note} {
    for {set component 48} {$component < 64} {incr component} {
        if {[lindex $modal_words [expr {$note*64+$component}]] ne "0000000000000000400"} {
            error {Unused canonical modal slots changed; review the scheduler before repacking}
        }
    }
}
puts {PASS modal ROM: three4096 banks match all128 notes/both presets}
