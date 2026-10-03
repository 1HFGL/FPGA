// A+B 单音联调顶层：只连接一个正弦波 DDS 与板载 DAC 输出链路。
// phase_inc 由外部同步逻辑提供；这里没有按键、包络、音量或复音处理。
// 本模块是联合仿真/后续验板入口，并非满足赛题要求的完整乐器。
module single_tone_demo_top #(
    parameter integer AUDIO_CLK_HZ = 25000000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter ROM_FILE = "rtl/rom/sine_1024.mem"
) (
    input  wire        clk_in,
    input  wire        rst_n,
    input  wire        audio_enable,
    input  wire [31:0] phase_inc,
    output wire        sample_underrun,
    output wire        i2s_bclk,
    output wire        i2s_lrclk,
    output wire        i2s_sdata,
    output wire        pa_en
);
    wire audio_ready;
    wire sample_request;
    wire signed [15:0] sample_data;
    wire sample_valid;

    // B 异步拉低、两拍同步释放复位；A 的高有效同步复位保持到 audio_ready。
    // 外部 rst_n 必须至少覆盖一个 clk_in 上升沿，才能清零 A 的同步状态。
    // 两个模块只用 clk_in；sample_request 是使能脉冲，不是另一个时钟。
    voice_dds #(.ROM_FILE(ROM_FILE)) u_voice_dds (
        .clk(clk_in),
        .rst(~audio_ready),
        .sample_tick(sample_request),
        .phase_inc(phase_inc),
        .sample(sample_data),
        .sample_valid(sample_valid)
    );

    synth_top #(
        .AUDIO_CLK_HZ(AUDIO_CLK_HZ),
        .SAMPLE_RATE_HZ(SAMPLE_RATE_HZ),
        .SAMPLE_BITS(16),
        .SLOT_BITS(16)
    ) u_synth_top (
        .clk_in(clk_in),
        .rst_n(rst_n),
        .audio_enable(audio_enable),
        .sample_data(sample_data),
        .sample_valid(sample_valid),
        .audio_ready(audio_ready),
        .sample_request(sample_request),
        .sample_underrun(sample_underrun),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_sdata(i2s_sdata),
        .pa_en(pa_en)
    );
endmodule
