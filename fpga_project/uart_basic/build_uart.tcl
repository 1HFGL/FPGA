# 独立项目；不能覆盖../impl/pnr的既有正常/自动试听位流。
open_project uart_basic.gprj
set_option -top_module instrument_uart_top
set_option -output_base_name instrument_uart
run all
