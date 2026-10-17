`timescale 1ns/1ps
// ADS1115 旋钮前端：I2C 采集 2 通道 -> 标定/量化 -> 2x7bit 参数。
// 对外接口与并行 adc_knob_if 一致（knob_value_flat + ready/fault），
// 便于 board_top 直接替换接入。
//
// 默认0..3.3V、PGA±4.096V（125uV/码），负值钳为0，端点映射到0/127。
// 主工程采用860SPS；两通道完成后成对发布。平滑由音频48kHz域负责，
// 此处不再叠加低速IIR和限速；若更改DR，必须同时重算CONV_WAIT与延迟预算。
module ads1115_knob_if #(
    parameter integer CLK_HZ        = 50000000,
    parameter integer I2C_HZ        = 350000,
    parameter [6:0]  I2C_ADDR       = 7'h48,
    parameter [2:0]  PGA            = 3'b001,   // +/-4.096V
    parameter [2:0]  DR             = 3'b111,   // 860 SPS
    parameter integer CH0_MUX       = 4,        // AIN0-GND
    parameter integer CH1_MUX       = 5,        // AIN1-GND
    // 1.5ms覆盖860SPS慢10%时的1.292ms转换并留启动余量；需实物复核。
    parameter integer CONV_WAIT     = (CLK_HZ / 2000) * 3,
    parameter integer READY_SAMPLES = 2,
    parameter integer FAULT_TIMEOUT = 5000000,
    parameter integer RAW_MIN_0     = 0,
    parameter integer RAW_MAX_0     = 26400,
    parameter integer RAW_MIN_1     = 0,
    parameter integer RAW_MAX_1     = 26400,
    parameter integer FILTER_SHIFT  = 0,
    parameter integer SLEW_STEP     = 127,
    parameter integer RETRY_WAIT    = CLK_HZ / 100
) (
    input  wire clk,
    input  wire rst_n,
    inout  wire sda,
    output wire scl,
    output wire [13:0] knob_value_flat,   // {knob1[6:0], knob0[6:0]}
    output wire knob_sample_valid,
    output wire param_ready,
    output wire param_fault
);

    wire [31:0] raw_flat;      // {chn1[15:0], chn0[15:0]}
    wire sample_valid;
    wire ads_fault;
    wire knob_fault;
    wire knob_ready;
    // Constant reciprocal multiplication avoids a large combinational divider.
    localparam integer SPAN_0 = (RAW_MAX_0 > RAW_MIN_0) ? RAW_MAX_0 - RAW_MIN_0 : 1;
    localparam integer SPAN_1 = (RAW_MAX_1 > RAW_MIN_1) ? RAW_MAX_1 - RAW_MIN_1 : 1;
    localparam [31:0] GAIN_0 = (2147418112 + SPAN_0 / 2) / SPAN_0;
    localparam [31:0] GAIN_1 = (2147418112 + SPAN_1 / 2) / SPAN_1;

    function [14:0] normalize_code;
        input [15:0] code;
        input integer low_code;
        input integer high_code;
        input [31:0] gain;
        reg [31:0] numerator;
        begin
            if (code[15] || (code <= low_code) || (high_code <= low_code))
                normalize_code = 15'd0;
            else if (code >= high_code)
                normalize_code = 15'h7fff;
            else begin
                numerator = (code - low_code) * gain + 32'd32768;
                normalize_code = numerator[30:16];
            end
        end
    endfunction

    reg [29:0] raw15;
    reg normalized_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw15 <= 30'd0;
            normalized_valid <= 1'b0;
        end else begin
            normalized_valid <= sample_valid && !ads_fault;
            if (sample_valid && !ads_fault) begin
                raw15 <= {
                    normalize_code(raw_flat[31:16], RAW_MIN_1, RAW_MAX_1, GAIN_1),
                    normalize_code(raw_flat[15:0], RAW_MIN_0, RAW_MAX_0, GAIN_0)
                };
            end
        end
    end

    ads1115_if #(
        .CLK_HZ       (CLK_HZ),
        .I2C_HZ       (I2C_HZ),
        .I2C_ADDR     (I2C_ADDR),
        .PGA          (PGA),
        .DR           (DR),
        .CH0_MUX      (CH0_MUX),
        .CH1_MUX      (CH1_MUX),
        .CONV_WAIT    (CONV_WAIT),
        .RETRY_WAIT   (RETRY_WAIT),
        // FPGA复位不等于ADC掉电：先让可能尚在进行的单次转换结束。
        .STARTUP_WAIT (CONV_WAIT + CLK_HZ / 10000)
    ) u_ads (
        .clk          (clk),
        .rst_n        (rst_n),
        .raw_flat     (raw_flat),
        .sample_valid (sample_valid),
        .fault        (ads_fault),
        .sda          (sda),
        .scl          (scl)
    );

    adc_knob_if #(
        .ADC_WIDTH     (15),
        .KNOB_COUNT    (2),
        .READY_SAMPLES (READY_SAMPLES),
        .FAULT_TIMEOUT (FAULT_TIMEOUT),
        .VALUE_WIDTH   (7),
        .SLEW_STEP     (SLEW_STEP),
        .FILTER_SHIFT  (FILTER_SHIFT)
    ) u_knob (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (normalized_valid && !ads_fault),
        .raw_flat     (raw15),
        .value_flat   (knob_value_flat),
        .param_valid  (knob_sample_valid),
        .ready        (knob_ready),
        .fault        (knob_fault)
    );

    assign param_fault = ads_fault | knob_fault;
    assign param_ready = knob_ready && !param_fault;

endmodule
