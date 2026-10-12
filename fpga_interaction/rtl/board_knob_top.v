`timescale 1ns/1ps
// 旋钮上板调试顶层：通过 ADS1115 采集两个旋钮，用 LED 指示状态。
//   LED[0] = param_ready（ADC 就绪）
//   LED[1] = param_fault（ADC 故障）
//   LED[2] = 旋钮0 最高位（转过中点会亮）
//   LED[3] = 旋钮1 最高位
module board_knob_top (
    input  wire sys_clk,
    input  wire sys_rst_n,
    inout  wire sda,
    output wire scl,
    output wire [3:0] LEDs
);

    wire rst_n_sync;
    wire [13:0] knob_value_flat;
    wire param_ready;
    wire param_fault;

    reset_sync u_reset_sync (
        .clk        (sys_clk),
        .raw_rst_n  (sys_rst_n),
        .rst_n_sync (rst_n_sync)
    );

    ads1115_knob_if #(
        .CLK_HZ    (50000000),
        .I2C_HZ    (100000),
        .I2C_ADDR  (7'h48),
        .PGA       (3'b001),
        .DR        (3'b100),
        .CH0_MUX   (4),
        .CH1_MUX   (5),
        .CONV_WAIT (500000)
    ) u_knob (
        .clk               (sys_clk),
        .rst_n             (rst_n_sync),
        .sda               (sda),
        .scl               (scl),
        .knob_value_flat   (knob_value_flat),
        .knob_sample_valid (),
        .param_ready       (param_ready),
        .param_fault       (param_fault)
    );

    assign LEDs[0] = param_ready;
    assign LEDs[1] = param_fault;
    assign LEDs[2] = knob_value_flat[6];   // 旋钮0 MSB
    assign LEDs[3] = knob_value_flat[13];  // 旋钮1 MSB

endmodule