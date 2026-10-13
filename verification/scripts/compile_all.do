# Main Verilog-only C compilation. Use source {absolute/path/to/compile_all.do}.
# Upstream SystemVerilog testbenches stay untouched and are not compiled here.
if {[info script] eq ""} {error "Use source, not do, to locate the script directory."}
set compile_script [info script]
if {[file pathtype $compile_script] ne "absolute"} {set compile_script [file join [pwd] $compile_script]}
set compile_root [file dirname [file dirname [file dirname $compile_script]]]
cd $compile_root
set compile_lib build/regression/c_compile_work
file mkdir [file dirname $compile_lib]
if {![file exists [file join $compile_lib _info]]} {vlib $compile_lib}
set compile_sources {}
foreach group {control common top audio synth display} {
    foreach source_file [glob -nocomplain [file join $compile_root rtl $group *.v]] {
        lappend compile_sources $source_file
    }
}
foreach relative_test {
    verification/tb/control/tb_input_sync_debounce.v
    verification/tb/control/tb_event_encoder.v
    verification/tb/control/tb_voice_allocator.v
} {lappend compile_sources [file join $compile_root $relative_test]}
vlog -vlog01compat -pedanticerrors -work $compile_lib {*}$compile_sources
puts "PASS compile_all: active C sources compiled in strict Verilog-2001; no upstream TB executed."
