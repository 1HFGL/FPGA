`timescale 1ns/1ps

module voice_gain (
    input  wire signed [15:0] wave_in,
    input  wire [15:0] env_in,
    output wire signed [15:0] sample_out
);

    wire signed [31:0] product;

    assign product = wave_in * $signed({1'b0, env_in});
    assign sample_out = product[30:15];

endmodule