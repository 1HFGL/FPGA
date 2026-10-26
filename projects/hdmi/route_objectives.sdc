# Identical edge models for routing objectives only. Original clocks remain active.
create_clock -name route_sys -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}] -add
create_generated_clock -name route_pixel -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 49 -divide_by 50 -add [get_pins {u_video_clock/u_pll/CLKOUT1}]
create_generated_clock -name route_usb -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 24 -divide_by 25 -add [get_pins {g_usb_touch.u_usb/u_clock/u_pll/CLKOUT0}]
create_generated_clock -name route_pin -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 24 -divide_by 25 -add [get_pins {g_usb_touch.u_usb/u_clock/u_pll/CLKOUT1}]
set_clock_uncertainty 2.100 -setup -from [get_clocks {route_sys}] -to [get_clocks {route_sys}]
set_clock_uncertainty 0.500 -hold -from [get_clocks {route_sys}] -to [get_clocks {route_sys}]
set_clock_uncertainty 2.100 -setup -from [get_clocks {route_pixel}] -to [get_clocks {route_pixel}]
set_clock_uncertainty 0.500 -hold -from [get_clocks {route_pixel}] -to [get_clocks {route_pixel}]
set_clock_uncertainty 2.100 -setup -from [get_clocks {route_usb}] -to [get_clocks {route_usb}]
set_clock_uncertainty 0.500 -hold -from [get_clocks {route_usb}] -to [get_clocks {route_usb}]
set_clock_uncertainty 2.100 -setup -from [get_clocks {route_usb}] -to [get_clocks {route_pin}]
set_clock_uncertainty 0.500 -hold -from [get_clocks {route_usb}] -to [get_clocks {route_pin}]
set_max_delay -from [get_clocks {route_pin}] -to [get_ports {usb_touch_dp usb_touch_dm}] 8.000
# Tighten only the routing alias for the measured packed shift connection.
set_min_delay -from [get_clocks {route_sys}] -through [get_pins {u_core/g_modal.u_bank/u_modal/g_dual.u_engine/u_group1/lfsr_lfsr_RAMREG_1_G[113]_s1/Q}] -to [get_regs {u_core/g_modal.u_bank/u_modal/g_dual.u_engine/u_group1/lfsr_lfsr_RAMREG_1_G[114]_s1}] 0.800
report_timing -setup -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -setup -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -setup -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to [get_ports {HP_BCK HP_DIN HP_WS PA_EN ble_tx knob_scl knob_sda uart_tx usb_touch_dm usb_touch_dp}] -max_paths 25 -max_common_paths 1
report_timing -hold -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -hold -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -hold -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to [get_ports {HP_BCK HP_DIN HP_WS PA_EN ble_tx knob_scl knob_sda uart_tx usb_touch_dm usb_touch_dp}] -max_paths 25 -max_common_paths 1
report_timing -recovery -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -recovery -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -recovery -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to [get_ports {HP_BCK HP_DIN HP_WS PA_EN ble_tx knob_scl knob_sda uart_tx usb_touch_dm usb_touch_dp}] -max_paths 25 -max_common_paths 1
report_timing -removal -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -removal -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -max_paths 25 -max_common_paths 1
report_exceptions -removal -from_clock [get_clocks {sys_clk hdmi_pixel hdmi_serial usb_clk usb_pin_clk}] -to [get_ports {HP_BCK HP_DIN HP_WS PA_EN ble_tx knob_scl knob_sda uart_tx usb_touch_dm usb_touch_dp}] -max_paths 25 -max_common_paths 1
report_timing -hold -from_clock [get_clocks {sys_clk}] -to_clock [get_clocks {sys_clk}] -from [get_regs {u_core/g_modal.u_bank/u_modal/g_dual.u_engine/u_group1/lfsr_lfsr_RAMREG_1_G[113]_s1}] -to [get_regs {u_core/g_modal.u_bank/u_modal/g_dual.u_engine/u_group1/lfsr_lfsr_RAMREG_1_G[114]_s1}] -max_paths 1 -max_common_paths 1
