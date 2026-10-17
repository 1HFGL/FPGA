# 与piano.sdc合用，49MHz像素和245MHz串行必须保留同步5倍关系。
create_generated_clock -name hdmi_serial -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 49 -divide_by 10 [get_pins {u_video_clock/u_pll/CLKOUT0}]
create_generated_clock -name hdmi_pixel -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 49 -divide_by 50 [get_pins {u_video_clock/u_pll/CLKOUT1}]
# HPD/LOCK只进入显示复位资格检查，不属于音频时钟/复位。
set_false_path -from [get_ports {hdmi_hpd}]
# 显示信箱：翻转控制只到第一级例外；稳定总线在同步请求后读取，保留20ns传输上界。
# 不使用整组异步时钟切除，以免隐藏像素到OSER的相关时钟路径。
set_false_path -through [get_pins {u_display/u_status/req_meta_s0/D u_display/u_status/ack_meta_s0/D u_display/u_sample/req_meta_s0/D u_display/u_sample/ack_meta_s0/D}]
set_max_delay -from [get_regs {u_display/u_status/hold_data* u_display/u_sample/hold_data*}] -to [get_regs {u_display/u_status/dst_data* u_display/u_sample/dst_data*}] 20.000
# 数据在请求前锁存，目的读取后还需等确认跨回源域才能改变，不存在同拍覆盖。
# 仅豁免这两组稳定总线的同边沿hold；max=20ns仍有效，不切setup或整个时钟组。
set_false_path -hold -from [get_regs {u_display/u_status/hold_data* u_display/u_sample/hold_data*}] -to [get_regs {u_display/u_status/dst_data* u_display/u_sample/dst_data*}]
# 异步复位只到同步释放链的CLEAR脚；级间D和其输出到普通寄存器/OSER的复位检查保留。
# 综合合并了相同像素释放链，实际名字为video_release；构建须检查约束命中。
set_false_path -through [get_pins {video_release_0_s0/CLEAR video_release_1_s0/CLEAR}]
# HDMI串行电气眼图/线缆及接收容限须实屏验证；这些约束不构成HDMI认证。
