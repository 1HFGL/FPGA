`timescale 1ns/1ps

module i2s_tx #(
    parameter integer BCLK_DIV = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_tick,
    input  wire signed [15:0] sample_in,
    output reg  bclk,
    output reg  lrck,
    output reg  sdata
);

    reg [15:0] shift_reg;
    reg [4:0] bit_cnt;
    reg [15:0] div_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'd0;
            bit_cnt <= 5'd0;
            div_cnt <= 16'd0;
            bclk <= 1'b0;
            lrck <= 1'b0;
            sdata <= 1'b0;
        end else begin
            if (sample_tick) begin
                shift_reg <= sample_in;
                bit_cnt <= 5'd0;
                lrck <= ~lrck;
            end

            if (div_cnt >= (BCLK_DIV - 1)) begin
                div_cnt <= 16'd0;
                bclk <= ~bclk;

                if (!bclk) begin
                    sdata <= shift_reg[15];
                    shift_reg <= {shift_reg[14:0], 1'b0};
                    if (bit_cnt == 5'd15) begin
                        bit_cnt <= 5'd0;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end
    end

endmodule