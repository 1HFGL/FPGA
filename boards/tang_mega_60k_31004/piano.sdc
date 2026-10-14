create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]
# 异步端口只扇出到各自首级同步器，首级->次级不排除。
# uart_rx在RTL中唯一使用处是u_uart/u_rx/rx_meta，构建后还须核对网表。
set_false_path -from [get_ports {uart_rx}]
set_false_path -from [get_ports {Key_in[0] Key_in[1]}]
set_false_path -from [get_ports {piano_key_n[0] piano_key_n[1] piano_key_n[2] piano_key_n[3] piano_key_n[4] piano_key_n[5] piano_key_n[6] piano_key_n[7] piano_key_n[8] piano_key_n[9] piano_key_n[10] piano_key_n[11] piano_key_n[12]}]
# 复位异步断言，统一通过B两拍同步释放。
set_false_path -from [get_ports {sys_rst_n}]
// SDA输入仅进入I2C接收同步器；SCL是系统时钟域使能输出，不是内部时钟。
set_false_path -from [get_ports {knob_sda}]
set_max_delay -to [get_ports {knob_sda knob_scl}] 20.000
set_min_delay -to [get_ports {knob_sda knob_scl}] 0.000
# 保留本地寄存器到引脚预算；不是DAC完整外部时序签核。
# UART TX对方是异步接收器；这里检查到引脚路径，不假设外部同步时钟。
set_max_delay -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN uart_tx}] 20.000
set_min_delay -to [get_ports {HP_BCK HP_WS HP_DIN PA_EN uart_tx}] 0.000
