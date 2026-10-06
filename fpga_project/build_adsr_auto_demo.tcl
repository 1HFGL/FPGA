# 新 ADSR 自动四声部版；约1秒按住，之后120ms释放；不操作板卡。
open_project fpga_project.gprj
set_option -top_module instrument_adsr_auto_top
set_option -output_base_name instrument_adsr_auto
run all
