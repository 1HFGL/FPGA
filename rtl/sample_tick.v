// B 的模块头：只声明接口，尚未实现时序逻辑。
// AUDIO_CLK_HZ 要按核实后的板卡时钟/PLL 配置填写，不能沿用 0。
module sample_tick #(
    parameter integer AUDIO_CLK_HZ = 0,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer SLOT_BITS = 32
) (
    input  wire clk_audio,
    input  wire rst_n,
    // 每半个 I2S 位时钟周期产生一个 clk_audio 周期宽的使能脉冲。
    output wire bclk_half_ce,
    // 每个左右声道完整帧开始时产生一个 clk_audio 周期宽的脉冲；
    // 同时向 A 请求下一帧的单声道 PCM 样本。
    output wire frame_start
);

    // TODO(B)：两个使能应来自同一个时钟计数体系，保证采样率与位时钟不漂移。

endmodule
