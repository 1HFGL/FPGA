`timescale 1ns/1ps

// 四个有符号 16 位样本混音。MIX_SHIFT=5 保留试听音量余量；
// MIX_SHIFT=0 可用于满增益混音，此时超出 16 位范围的结果饱和。
module sample_mixer4 #(
    parameter integer MIX_SHIFT = 5 // 有效范围 0~17，单位为二进制右移位数
) (
    input  wire               clk,
    input  wire               rst, // 高有效同步复位
    input  wire               in_valid,
    input  wire [63:0]        samples_flat, // 声部 0 在最低 16 位
    output reg signed [15:0]  sample_out,
    output reg                out_valid,
    output reg                clipped // 仅有效输出拍报告饱和
);
    wire signed [15:0] s0 = samples_flat[15:0];
    wire signed [15:0] s1 = samples_flat[31:16];
    wire signed [15:0] s2 = samples_flat[47:32];
    wire signed [15:0] s3 = samples_flat[63:48];
    // 先扩位再相加：两路需要 17 位，四路需要 18 位。
    // 分成两组求和，避免形成三个串联加法器。
    wire signed [16:0] pair01 = $signed({s0[15],s0}) + $signed({s1[15],s1});
    wire signed [16:0] pair23 = $signed({s2[15],s2}) + $signed({s3[15],s3});
    wire signed [17:0] total = $signed({pair01[16],pair01}) +
                               $signed({pair23[16],pair23});
    wire signed [17:0] scaled = total >>> MIX_SHIFT;

    // 算术右移向负无穷取整；先饱和再截位，禁止溢出后符号反转。
    always @(posedge clk) begin
        if (rst) begin
            sample_out <= 16'sd0;
            out_valid <= 1'b0;
            clipped <= 1'b0;
        end else begin
            out_valid <= in_valid;
            clipped <= 1'b0;
            if (in_valid) begin
                if (scaled > 18'sd32767) begin
                    sample_out <= 16'sh7fff;
                    clipped <= 1'b1;
                end else if (scaled < -18'sd32768) begin
                    sample_out <= 16'sh8000;
                    clipped <= 1'b1;
                end else sample_out <= scaled[15:0];
            end
        end
    end
endmodule
