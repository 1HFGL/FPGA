# Legacy abstract single_tone_demo_top clock, NOT the 31004 V22 board clock.
# This constrains only the primary clock, not the complete external interface.
create_clock -name clk_in -period 40.000 -waveform {0.000 20.000} [get_ports {clk_in}]
