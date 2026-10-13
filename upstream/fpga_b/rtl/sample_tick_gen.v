`timescale 1ns/1ps

module sample_tick_gen #(
    parameter integer CLK_HZ      = 50000000,
    parameter integer SAMPLE_RATE = 48000,
    parameter integer CNT_WIDTH   = 16
) (
    input  wire clk,
    input  wire rst_n,
    output reg  sample_tick
);

    localparam integer DIVIDER = (CLK_HZ / SAMPLE_RATE);

    reg [CNT_WIDTH-1:0] div_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= {CNT_WIDTH{1'b0}};
            sample_tick <= 1'b0;
        end else if (div_cnt >= (DIVIDER - 1)) begin
            div_cnt <= {CNT_WIDTH{1'b0}};
            sample_tick <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
            sample_tick <= 1'b0;
        end
    end

endmodule