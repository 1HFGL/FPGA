`timescale 1ns/1ps

// 参数化有符号16位样本混音，保留模块名兼容接口。MIX_SHIFT=5保留试听余量；
// MIX_SHIFT=0 可用于满增益混音，此时超出 16 位范围的结果饱和。
// 本模块不分配声部，也不产生音色，只将同一采样时刻的四路振幅相加。
// 四个最小值之和为-131072，需要18位带符号数，不能用16位直接相加。
// 默认右移5位相当于总和除32，是刻意保守的试听电平，不是按声部数自动归一化。
// clipped只表示数字端削波；未削波不代表耳机实际声压一定安全。
module sample_mixer4 #(
    parameter integer MIX_SHIFT = 5,
    parameter integer VOICES = 4
) (
    input  wire               clk,
    input  wire               rst, // 高有效同步复位
    input  wire               in_valid,
    input  wire [VOICES*16-1:0] samples_flat,
    output reg signed [15:0]  sample_out,
    output reg                out_valid,
    output reg                clipped // 仅有效输出拍报告饱和
);
    localparam integer LEVELS=(VOICES>1)?$clog2(VOICES):0;
    localparam integer LEAVES=2**LEVELS;
    localparam integer SUM_WIDTH=16+LEVELS;
    wire signed [SUM_WIDTH-1:0] tree [1:2*LEAVES-1];
    genvar n;
    // 平衡加法树：16路只经过4级加法，空叶补零，所有加法先扩位。
    generate
        for(n=0;n<LEAVES;n=n+1) begin:g_leaf
            if(n<VOICES) begin:g_used
                assign tree[LEAVES+n]={{LEVELS{samples_flat[n*16+15]}},samples_flat[n*16+:16]};
            end else begin:g_unused
                assign tree[LEAVES+n]=0;
            end
        end
        for(n=1;n<LEAVES;n=n+1) begin:g_sum
            assign tree[n]=tree[2*n]+tree[2*n+1];
        end
    endgenerate
    wire signed [SUM_WIDTH-1:0] scaled=tree[1] >>> MIX_SHIFT;

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
                if (scaled > 32767) begin
                    sample_out <= 16'sh7fff;
                    clipped <= 1'b1;
                end else if (scaled < -32768) begin
                    sample_out <= 16'sh8000;
                    clipped <= 1'b1;
                end else sample_out <= scaled[15:0];
            end
        end
    end
endmodule
