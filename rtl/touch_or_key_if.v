`timescale 1ns/1ps

// 多键外壳：每个输入独立实例化一套同步/消抖电路，支持同时按多个键。
// 名字含touch但这里只接收数字电平，不会测量电容触摸或模拟压力。
// 当前板级raw_key[0]/[1]分别来自KEY1/KEY2；KEY0单独走全局复位。
module touch_or_key_if #(
    parameter integer KEY_COUNT       = 2,
    parameter integer ACTIVE_LOW      = 1,
    parameter integer DEBOUNCE_CYCLES = 250000
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
