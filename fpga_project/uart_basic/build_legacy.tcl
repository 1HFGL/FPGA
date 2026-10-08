# 旧工程的复制品在results内构建，不能覆盖原来的试听输出。
open_project ../../results/uart-basic-20261008/legacy_rebuild/legacy_check.gprj
set_option -top_module instrument_adsr_top
set_option -output_base_name instrument_adsr_check
run all
