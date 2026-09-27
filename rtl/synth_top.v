// B 的模块头：计划中的整机顶层，尚未实现连接逻辑。
// C 确认传感器接口后，再补实际输入端口；当前不可直接用于上板。
module synth_top #(
    parameter integer AUDIO_CLK_HZ = 0,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer SAMPLE_BITS = 16,
    parameter integer SLOT_BITS = 32
) (
    input  wire clk_in,
    input  wire rst_n,
    output wire i2s_bclk,
    output wire i2s_lrclk,
    output wire i2s_sdata
);

    // TODO(B)：按已核实的板卡时钟和音频芯片要求建立 clk_audio/复位，
    //          在此例化 sample_tick 与 i2s_tx。
    // TODO(B+C)：补实际传感器输入端口，并接入 C 的事件链路。
    // TODO(B+A)：把 frame_start 接到 A 的样本请求，把 A 的有符号 PCM
    //            样本及 valid 接到 i2s_tx；连接前约定好流水线延迟。
    // TODO(B)：板载音频电路确有要求时，再加入芯片配置和 MCLK。

endmodule
