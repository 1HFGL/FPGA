`timescale 1ns/1ps

// NEO Dock 31004 板载按键试听。KEY0复位；KEY1弹C4；KEY2切换乐器。
// 只驱动第0声部，便于同音高比较两套预设，不代表四键演奏接口。
// 所有逻辑使用V22的50MHz时钟；PT8211-S串行格式沿用已验证的B模块。
module instrument_presets_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter [31:0] G_ATTACK=64, G_DECAY=32768, G_RELEASE=4096,
    parameter [16:0] G_SUSTAIN=0,
    parameter [31:0] S_ATTACK=1024, S_DECAY=8192, S_RELEASE=8192,
    parameter [16:0] S_SUSTAIN=49152,
    parameter [31:0] G_TONE_SAMPLES=8192, S_TONE_SAMPLES=2048
) (
    input wire sys_clk, sys_rst_n,
    input wire [1:0] Key_in,
    output wire HP_BCK, HP_WS, HP_DIN, PA_EN
);
    wire audio_ready, sample_request, sample_underrun;
    wire [1:0] key_level, key_press, key_release;
    reg selected_instrument;
    reg play_gate, play_trigger;
    wire [3:0] voice_gate={3'b0,play_gate};
    wire [3:0] voice_retrigger={3'b0,play_trigger};
    wire [3:0] voice_instrument={3'b0,selected_instrument};
    wire [3:0] voice_active, release_done, instrument_active;
    wire [67:0] env_level_flat, tone_level_flat;
    wire signed [15:0] sample_data;
    wire sample_valid, sample_clipped, sounding;
    genvar k;
    generate for(k=0;k<2;k=k+1) begin: g_key
        input_sync_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key (
            .clk(sys_clk),.rst_n(audio_ready),.async_in(Key_in[k]),
            .level(key_level[k]),.press_pulse(key_press[k]),.release_pulse(key_release[k]));
    end endgenerate

    // 消抖器的level先于press_pulse更新；以事件统一更新gate和trigger，
    // 避免恰好遇到采样边界时先自然起音、随后又被同一次按键重触发。
    // 两键同时按下时，选色与触发同拍注册，下一拍核心采到新乐器。
    always @(posedge sys_clk) begin
        if(!audio_ready) begin
            selected_instrument<=0; play_gate<=0; play_trigger<=0;
        end else begin
            play_trigger<=key_press[0] && !key_release[0];
            if(key_press[1]) selected_instrument<=~selected_instrument;
            if(key_press[0]) play_gate<=1;
            if(key_release[0]) play_gate<=0;
        end
    end
    voice_bank_instruments #(
        .G_ATTACK(G_ATTACK),.G_DECAY(G_DECAY),.G_SUSTAIN(G_SUSTAIN),.G_RELEASE(G_RELEASE),
        .S_ATTACK(S_ATTACK),.S_DECAY(S_DECAY),.S_SUSTAIN(S_SUSTAIN),.S_RELEASE(S_RELEASE),
        .G_TONE_SAMPLES(G_TONE_SAMPLES),.S_TONE_SAMPLES(S_TONE_SAMPLES),.MIX_SHIFT(5)
    ) u_bank (
        .clk(sys_clk),.rst_n(audio_ready),.sample_request(sample_request),
        .voice_gate(voice_gate),.voice_retrigger(voice_retrigger),.voice_instrument(voice_instrument),
        .voice_note_flat({21'd0,7'd60}),.voice_velocity_flat({21'd0,7'd100}),
        .voice_active(voice_active),.release_done(release_done),.sounding(sounding),
        .env_level_flat(env_level_flat),.tone_level_flat(tone_level_flat),.instrument_active(instrument_active),
        .sample_data(sample_data),.sample_valid(sample_valid),.sample_clipped(sample_clipped));

    // B还有待发/正在发送的整帧。核心静音后再留3帧，避免切断最后的尾音；
    // KEY0复位仍会由B立即关功放。这里不改变数字样本或其R4有效时刻。
    reg [1:0] drain_frames;
    always @(posedge sys_clk) begin
        if(!audio_ready) drain_frames<=0;
        else if(sample_request) begin
            if(sounding) drain_frames<=3;
            else if(drain_frames!=0) drain_frames<=drain_frames-1'b1;
        end
    end
    synth_top #(.AUDIO_CLK_HZ(50000000),.SAMPLE_RATE_HZ(48000)) u_b (
        .clk_in(sys_clk),.rst_n(sys_rst_n),.audio_enable(sounding || drain_frames!=0),
        .sample_data(sample_data),.sample_valid(sample_valid),.audio_ready(audio_ready),
        .sample_request(sample_request),.sample_underrun(sample_underrun),
        .i2s_bclk(HP_BCK),.i2s_lrclk(HP_WS),.i2s_sdata(HP_DIN),.pa_en(PA_EN),
        .frame_start()); // 此例程的请求仍等于帧边界；不使用新增观察口。
endmodule
