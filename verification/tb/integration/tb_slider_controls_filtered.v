`timescale 1ns/1ps
// Reuse the existing timed ADC test unchanged, enabling the formal knob filter.
module tb_slider_controls_filtered;
    tb_slider_controls run();
    defparam run.dut.HYSTERESIS_COUNTS=384;
endmodule
