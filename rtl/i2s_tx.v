// B 的模块头：只声明接口，尚未实现串行发送逻辑。
module i2s_tx #(
    parameter integer SAMPLE_BITS = 16,
    parameter integer SLOT_BITS = 32
) (
    input  wire clk_audio,
    input  wire rst_n,
    input  wire bclk_half_ce,
    input  wire frame_start,
    // A 提供的有符号补码单声道样本；valid 为一个 clk_audio 周期的脉冲。
    input  wire signed [SAMPLE_BITS-1:0] sample_data,
    input  wire sample_valid,
    output wire i2s_bclk,
    output wire i2s_lrclk,
    output wire i2s_sdata,
    // 帧边界前未收到新样本时置位，用于定位断音。
    output wire sample_underrun
);

    // TODO(B)：frame_start 后接收 sample_valid，锁存样本供下一帧左右声道发送。
    // 复位或没有新样本时输出数字零；不要把失效样本误当成有效声音。
    // 对照实际原理图和音频芯片手册核对时隙宽度、左右声道极性、
    // I2S 的一位延迟及是否需要主时钟 MCLK。

endmodule
