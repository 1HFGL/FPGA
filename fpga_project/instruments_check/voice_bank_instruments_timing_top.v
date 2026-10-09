`timescale 1ns/1ps

// 仅用于独立实现时序验证，不是乐器板级顶层，不能直接下载到板卡。
// 在同一个 clk 下，用输入/输出寄存器模拟 C/B 模块的同步接口边界。
// 因此“音符查表 -> 相位累加”以及尾音反馈也纳入 20 ns 检查。
// 外壳额外增加输入一拍、输出一拍；实际核心仍保持 R4 输出。
module voice_bank_instruments_timing_top (
    input wire clk,
    input wire rst_n,
    input wire sample_request,
    input wire [3:0] voice_gate, voice_retrigger,
    input wire [3:0] voice_instrument,
    input wire [27:0] voice_note_flat, voice_velocity_flat,
    output reg [3:0] release_done, voice_active,
    output reg [67:0] env_level_flat, tone_level_flat,
    output reg [3:0] instrument_active,
    output reg sounding,
    output reg signed [15:0] sample_data,
    output reg sample_valid, sample_clipped
);
    reg rst_n_q, sample_request_q;
    reg [3:0] gate_q, retrigger_q;
    reg [3:0] instrument_q;
    reg [27:0] note_q, velocity_q;
    wire [3:0] done_core, active_core;
    wire [67:0] env_core, tone_core;
    wire [3:0] instrument_core;
    wire sounding_core, valid_core, clipped_core;
    wire signed [15:0] sample_core;

    // 所有控制同拍送入核心，外壳不生成采样时钟或包络。
    always @(posedge clk) begin
        rst_n_q <= rst_n;
        sample_request_q <= sample_request;
        gate_q <= voice_gate;
        retrigger_q <= voice_retrigger;
        instrument_q <= voice_instrument;
        note_q <= voice_note_flat;
        velocity_q <= voice_velocity_flat;
        release_done <= done_core;
        voice_active <= active_core;
        env_level_flat <= env_core;
        tone_level_flat <= tone_core;
        instrument_active <= instrument_core;
        sounding <= sounding_core;
        sample_data <= sample_core;
        sample_valid <= valid_core;
        sample_clipped <= clipped_core;
    end

    voice_bank_instruments u_bank (
        .clk(clk), .rst_n(rst_n_q), .sample_request(sample_request_q),
        .voice_gate(gate_q), .voice_retrigger(retrigger_q), .voice_instrument(instrument_q),
        .voice_note_flat(note_q), .voice_velocity_flat(velocity_q),
        .release_done(done_core), .voice_active(active_core),
        .env_level_flat(env_core), .tone_level_flat(tone_core),
        .instrument_active(instrument_core), .sounding(sounding_core),
        .sample_data(sample_core), .sample_valid(valid_core),
        .sample_clipped(clipped_core)
    );
endmodule
