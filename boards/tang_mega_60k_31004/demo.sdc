# V22 SOM OSC nominal 50MHz. MS5351 AB12 is not used.
create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]
# Asynchronous keys fan out only to first-stage synchronizers.
# Do not exclude sync_meta -> sync_q or downstream synchronous logic.
set_false_path -from [get_ports {Key_in[0] Key_in[1]}]
# External active-low reset asserts asynchronously; release is synchronized in B.
set_false_path -from [get_ports {sys_rst_n}]
# Local register-to-pad budgets, NOT a complete DAC external timing signoff.
# BCK is an output, not an internal generated clock. All logic uses sys_clk.
set_max_delay -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN}] 20.000
set_min_delay -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN}] 0.000
