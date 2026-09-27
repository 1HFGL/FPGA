`timescale 1ns/1ps

// One DDS voice. All logic uses clk; sample_tick is a clock enable.
module voice_dds #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem"
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire [31:0]        phase_inc,
    output wire signed [15:0] sample,
    output wire               sample_valid
);
    wire [31:0] phase;
    wire [9:0] wave_addr;

    phase_acc u_phase_acc (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .phase_inc(phase_inc),
        .phase(phase),
        .wave_addr(wave_addr)
    );

    // Both modules sample their inputs at the same rising edge.
    // The ROM reads the OLD phase address; phase then advances for next time.
    // sample and sample_valid update after that same edge.
    wave_lut #(.ROM_FILE(ROM_FILE)) u_wave_lut (
        .clk(clk),
        .rst(rst),
        .read_en(sample_tick),
        .addr(wave_addr),
        .sample(sample),
        .sample_valid(sample_valid)
    );
endmodule
