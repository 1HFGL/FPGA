`timescale 1ns/1ps

module touch_or_key_if #(
    parameter integer KEY_COUNT       = 2,
    parameter integer ACTIVE_LOW      = 1,
    parameter integer DEBOUNCE_CYCLES = 250000 // 5 ms at 50 MHz
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [KEY_COUNT-1:0] raw_key,
    output wire [KEY_COUNT-1:0] key_level,
    output wire [KEY_COUNT-1:0] key_press,
    output wire [KEY_COUNT-1:0] key_release
);

    genvar i;

    generate
        for (i = 0; i < KEY_COUNT; i = i + 1) begin : g_key
            input_sync_debounce #(
                .ACTIVE_LOW      (ACTIVE_LOW),
                .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES)
            ) u_debounce (
                .clk           (clk),
                .rst_n         (rst_n),
                .async_in      (raw_key[i]),
                .level         (key_level[i]),
                .press_pulse   (key_press[i]),
                .release_pulse (key_release[i])
            );
        end
    endgenerate

endmodule
