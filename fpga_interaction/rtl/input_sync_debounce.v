`timescale 1ns/1ps

module input_sync_debounce #(
    parameter integer ACTIVE_LOW      = 1,
    parameter integer DEBOUNCE_CYCLES = 250000, // 5 ms at 50 MHz
    parameter integer CNT_WIDTH       = 32
) (
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire level,
    output reg  press_pulse,
    output reg  release_pulse
);

    reg sync_meta;
    reg sync_q;
    reg stable;
    reg stable_d;
    reg [CNT_WIDTH-1:0] debounce_cnt;

    wire raw_level = (ACTIVE_LOW != 0) ? ~sync_q : sync_q;

    assign level = stable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_meta <= (ACTIVE_LOW != 0) ? 1'b1 : 1'b0;
            sync_q    <= (ACTIVE_LOW != 0) ? 1'b1 : 1'b0;
        end else begin
            sync_meta <= async_in;
            sync_q    <= sync_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable       <= 1'b0;
            stable_d     <= 1'b0;
            debounce_cnt <= {CNT_WIDTH{1'b0}};
        end else begin
            stable_d <= stable;

            if (raw_level != stable) begin
                if ((DEBOUNCE_CYCLES <= 1) || (debounce_cnt >= (DEBOUNCE_CYCLES - 1))) begin
                    stable       <= raw_level;
                    debounce_cnt <= {CNT_WIDTH{1'b0}};
                end else begin
                    debounce_cnt <= debounce_cnt + 1'b1;
                end
            end else begin
                debounce_cnt <= {CNT_WIDTH{1'b0}};
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            press_pulse   <= 1'b0;
            release_pulse <= 1'b0;
        end else begin
            press_pulse   <= stable & ~stable_d;
            release_pulse <= ~stable & stable_d;
        end
    end

endmodule
