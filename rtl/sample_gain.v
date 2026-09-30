`timescale 1ns/1ps

// One registered signed-audio x unsigned-envelope multiply.
module sample_gain (
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    input  wire [16:0]        gain,
    output reg signed [15:0] sample_out,
    output reg                out_valid
);
    // Clamp invalid gains; unity is represented exactly, not as 65535.
    wire [16:0] bounded_gain = (gain > 17'd65536) ? 17'd65536 : gain;
    wire signed [17:0] positive_gain = $signed({1'b0, bounded_gain});
    wire signed [33:0] product = $signed(sample_in) * positive_gain;
    wire signed [33:0] scaled = product >>> 16;

    // Arithmetic shift rounds toward minus infinity (error < 1 output LSB).
    // gain <= 1 guarantees scaled fits signed 16 bits, including -32768.
    always @(posedge clk) begin
        if (rst) begin
            sample_out <= 16'sd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid)
                sample_out <= scaled[15:0];
        end
    end
endmodule
