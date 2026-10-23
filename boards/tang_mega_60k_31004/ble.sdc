# 两个异步输入仅连接各自首级同步器，首级到次级仍按sys_clk分析。
set_false_path -from [get_ports {ble_rx}]
set_false_path -from [get_ports {ble_state}]
# UART接收异步；保留寄存器到引脚20ns/0ns预算，不冒充外部同步时序。
set_max_delay -to [get_ports {ble_tx}] 20.000
set_min_delay -to [get_ports {ble_tx}] 0.000
