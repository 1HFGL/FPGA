# Same device/pins, one-shot four-voice playback after reset.
# This builds only; it does not program any hardware.
open_project fpga_project.gprj
set_option -top_module instrument_demo_auto_top
set_option -output_base_name instrument_demo_auto
run all
