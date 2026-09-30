# Run: gw_sh build_demo.tcl (working directory: fpga_project).
# This builds only; it does not program any hardware.
open_project fpga_project.gprj
set_option -top_module instrument_demo_top
set_option -output_base_name instrument_demo
run all
