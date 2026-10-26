# 每个端口只扇出到对应去抖器的首级同步触发器；内部级间仍做时序分析。
set_false_path -from [get_ports {function_key_n[0]}]
set_false_path -from [get_ports {function_key_n[1]}]
set_false_path -from [get_ports {function_key_n[2]}]
