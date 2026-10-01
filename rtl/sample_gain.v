`timescale 1ns/1ps

// 有符号 16 位音频乘无符号 Q1.16 增益；计算结果寄存输出。
module sample_gain (
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    input  wire [16:0]        gain,
    output reg signed [15:0] sample_out,
    output reg                out_valid
);
    // 65536 恰好是 1 倍增益；输入超过 1 倍时钳位，防止输出溢出。
    wire [16:0] bounded_gain=(gain>17'd65536)?17'd65536:gain;
    // 先在最高位补 0，再解释为有符号数，否则满幅增益可能被误认为负数。
    wire signed [17:0] positive_gain=$signed({1'b0,bounded_gain});
    wire signed [33:0] product=$signed(sample_in)*positive_gain;
    wire signed [33:0] scaled=product>>>16;

    // 右移 16 位还原 Q1.16 的缩放，向负无穷舍入，误差小于 1 LSB。
    // 增益在 0~1，故结果仍在 -32768~32767；截取低 16 位不会溢出。
    always @(posedge clk) begin
        if (rst) begin
            sample_out<=16'sd0;
            out_valid<=1'b0;
        end else begin
            out_valid<=in_valid;
            // 无效周期保持样本，但 out_valid 为 0，下游不应读取该值。
            if (in_valid) sample_out<=scaled[15:0];
        end
    end
endmodule
