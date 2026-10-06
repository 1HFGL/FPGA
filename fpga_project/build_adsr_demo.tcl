# 新 ADSR 版，单独输出，不覆盖旧 instrument_demo.fs；不操作板卡。
open_project fpga_project.gprj
set_option -top_module instrument_adsr_top
set_option -output_base_name instrument_adsr
run all
