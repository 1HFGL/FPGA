// B 的音频输出集成顶层。A 提供已混音、已限幅的 16 位补码样本；
// 本模块只负责输出；当前整机由 instrument_adsr_top 连接 A/C，不在这里读按键。
// 默认 25 MHz 仅供通用仿真；31004 板级顶层明确覆盖为 V22 的 50 MHz。
// B部分建议阅读顺序：本文件 -> sample_tick.v -> i2s_tx.v。
// 每个帧边界一边发送上次缓存的样本，一边发出下一样本请求。
// 当前A在请求R0后的R3给出有效样本，发送器在R4缓存，在下一帧才上串行线。
// 因此“计算用4拍”不等于“按键到耳机延迟”；还包含消抖、等帧和模拟电路。
module synth_top #(
    parameter integer AUDIO_CLK_HZ = 25000000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer SAMPLE_BITS = 16,
    parameter integer SLOT_BITS = 16
) (
    input  wire clk_in,
    input  wire rst_n,
    // audio_enable 必须与 clk_in 同步；拉低可关闭低有效功放使能。
    input  wire audio_enable,
    // A 必须在相邻两个 sample_request 之间返回单周期 sample_valid。
    input  wire signed [SAMPLE_BITS-1:0] sample_data,
    input  wire sample_valid,
    // 同步释放后的音频域就绪信号；上游同步模块可据此保持复位。
    output wire audio_ready,
    output wire sample_request,
    output wire sample_underrun,
    output wire i2s_bclk,
    output wire i2s_lrclk,
    output wire i2s_sdata,
    output wire pa_en,
    // 真正发送帧边界；不得把它与可配置的样本准备事件混为一谈。
    output wire frame_start
);

    // 异步拉低复位；释放时经过 clk_in 两个上升沿。
    // B 内部只有 clk_in 一个时钟域，BCK 仅作为输出信号使用。
    reg [1:0] reset_release;
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n)
            reset_release <= 2'b00;
        else
            reset_release <= {reset_release[0], 1'b1};
    end

    wire audio_rst_n = reset_release[1];
    assign audio_ready = audio_rst_n;
    wire bclk_half_ce;

    sample_tick #(
        .AUDIO_CLK_HZ(AUDIO_CLK_HZ),
        .SAMPLE_RATE_HZ(SAMPLE_RATE_HZ),
        .SLOT_BITS(SLOT_BITS)
    ) u_sample_tick (
        .clk_audio(clk_in),
        .rst_n(audio_rst_n),
        .bclk_half_ce(bclk_half_ce),
        .frame_start(frame_start)
    );

    i2s_tx #(
        .SAMPLE_BITS(SAMPLE_BITS),
        .SLOT_BITS(SLOT_BITS)
    ) u_i2s_tx (
        .clk_audio(clk_in),
        .rst_n(audio_rst_n),
        .bclk_half_ce(bclk_half_ce),
        .frame_start(frame_start),
        .sample_data(sample_data),
        .sample_valid(sample_valid),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_sdata(i2s_sdata),
        .sample_underrun(sample_underrun)
    );

    assign sample_request = frame_start;
    // sounding由A判断是否仍有保持音/释放尾音；不能直接用按键电平代替，
    // 否则松键会立刻关输出，ADSR的120ms释放尾音就听不到了。
    // 31004 原理图标明 PA_EN=1 关闭、PA_EN=0 开启。
    assign pa_en = ~(audio_rst_n & audio_enable);

endmodule
