`timescale 1ns/1ps

module board_test_top (
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire [1:0] Key_in,
    output wire [3:0] LEDs
);

    board_top #(
        .TEST_MODE        (1),
        .TEST_VOICES      (32),
        .TEST_HOLD_CYCLES (50000000)
    ) u_board_top (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .Key_in    (Key_in),
        .LEDs      (LEDs)
    );

endmodule