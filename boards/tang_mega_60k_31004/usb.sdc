# USB full-speed PHY runs at 48MHz, independent of audio/video service.
create_generated_clock -name usb_clk -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 24 -divide_by 25 [get_pins {g_usb_touch.u_usb/u_clock/u_pll/CLKOUT0}]
# D+/D- use clock recovery/oversampling. Only the first metastability stages are cut.
set_false_path -from [get_ports {usb_touch_dp usb_touch_dm}] -to [get_pins {g_usb_touch.u_usb/u_port/u_phy/rx_dp_ms_s0/D g_usb_touch.u_usb/u_port/u_phy/rx_dn_ms_s0/D g_usb_touch.u_usb/u_port/u_phy/rxd_ms_s0/D g_usb_touch.u_usb/u_port/line_meta_0_s0/D g_usb_touch.u_usb/u_port/line_meta_1_s0/D}]
# Request/acknowledge and link presence cross only through two-flop synchronizers.
set_false_path -through [get_pins {g_usb_touch.u_usb/u_reports/req_meta_s0/D g_usb_touch.u_usb/u_reports/ack_meta_s0/D g_usb_touch.u_usb/connected_meta_s0/D}]
# Payload is held before request and until the returned acknowledgement.
set_max_delay -from [get_regs {g_usb_touch.u_usb/u_reports/hold_data*}] -to [get_regs {g_usb_touch.u_usb/u_reports/dst_data*}] 20.000
set_false_path -hold -from [get_regs {g_usb_touch.u_usb/u_reports/hold_data*}] -to [get_regs {g_usb_touch.u_usb/u_reports/dst_data*}]
set_false_path -through [get_pins {g_usb_touch.u_usb/usb_release_0_s0/CLEAR g_usb_touch.u_usb/usb_release_1_s0/CLEAR}]
# Digital launch budget (<half a 48MHz cycle); not USB electrical certification.
set_max_delay -to [get_ports {usb_touch_dp usb_touch_dm}] 10.000

# Pin-only output of the same PLL: same 48MHz ratio and zero phase.
create_generated_clock -name usb_pin_clk -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 24 -divide_by 25 [get_pins {g_usb_touch.u_usb/u_clock/u_pll/CLKOUT1}]
