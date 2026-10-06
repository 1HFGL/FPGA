// 板级接入 A 的 voice_bank_adsr 与 sample_mixer4；旧 demo 和旧 bank 保留。
// 31004：V22=50MHz，KEY0复位，KEY1=C4，KEY2=E4；不新增引脚或外设。
module instrument_adsr_top #(
    parameter integer AUTO_TEST = 0,
    parameter integer DEBOUNCE_CYCLES = 250000,
    parameter integer TEST_HOLD_CYCLES = 50000000,
    parameter [31:0] ATTACK_SAMPLES = 32'd96,
    parameter [31:0] DECAY_SAMPLES = 32'd24000,
    parameter [16:0] SUSTAIN_LEVEL = 17'd6554,
    parameter [31:0] RELEASE_SAMPLES = 32'd5760
) (
    input wire sys_clk,
    input wire sys_rst_n,
    input wire [1:0] Key_in,
    output wire HP_BCK,
    output wire HP_WS,
    output wire HP_DIN,
    output wire PA_EN
);
    wire audio_ready, sample_request, sample_underrun;
    wire [3:0] voice_gate, voice_active, voice_trigger, release_done;
    wire [27:0] voice_note_flat, voice_velocity_flat;
    wire [5:0] voice_count;
    wire signed [15:0] sample_data;
    wire sample_valid, sounding, sample_clipped;
    interaction_top #(
        .KEY_COUNT(2), .VOICES(4), .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .TEST_HOLD_CYCLES(TEST_HOLD_CYCLES)
    ) u_c (
        .clk(sys_clk), .rst_n(audio_ready), .key_n(Key_in),
        .key_velocity_flat({7'd100,7'd100}),
        .pressure_valid(1'b0), .pressure_raw(12'd0), .release_done(release_done),
        .expr_valid(1'b0), .expr_source_id(5'd0), .expr_note(7'd0),
        .expr_pitch_bend(16'd0), .expr_aftertouch(8'd0),
        .expr_vibrato_depth(8'd0), .expr_vibrato_rate(8'd0),
        .test_enable(AUTO_TEST != 0), .test_clear(1'b0), .test_voices(6'd4),
        .voice_active(voice_active), .voice_gate(voice_gate), .voice_trigger(voice_trigger),
        .voice_note_flat(voice_note_flat), .voice_velocity_flat(voice_velocity_flat),
        .voice_count(voice_count),
        .key_level(), .key_press(), .key_release(), .pressure_velocity(), .pressure_active(),
        .event_valid(), .event_type(), .event_source_id(), .event_note(),
        .event_velocity(), .event_timbre(), .expr_ready(), .test_busy(), .test_done(),
        .voice_source_id_flat(), .voice_timbre_flat(), .voice_pitch_bend_flat(),
        .voice_aftertouch_flat(), .voice_vibrato_depth_flat(), .voice_vibrato_rate_flat(),
        .max_voice_count(), .note_on_count(), .note_off_count(), .steal_count(), .steal_pulse()
    );
    // C 的 voice_trigger 是分配完成后的单拍脉冲，对应 A 的 voice_retrigger。
    // 请求 R0 -> A 混音有效 R3 -> B 同步缓存 R4；仍保持 /32 试听音量。
    // A 的 voice_active 不连接 C 的同名输出，避免两个模块同时驱动一根线。
    voice_bank_adsr #(
        .ATTACK_SAMPLES(ATTACK_SAMPLES), .DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .RELEASE_SAMPLES(RELEASE_SAMPLES),
        .MIX_SHIFT(5)
    ) u_bank (
        .clk(sys_clk), .rst_n(audio_ready), .sample_request(sample_request),
        .voice_gate(voice_gate), .voice_retrigger(voice_trigger),
        .voice_note_flat(voice_note_flat), .voice_velocity_flat(voice_velocity_flat),
        .release_done(release_done), .sounding(sounding),
        .sample_data(sample_data), .sample_valid(sample_valid), .env_level_flat(),
        .voice_active(), .sample_clipped(sample_clipped)
    );
    synth_top #(.AUDIO_CLK_HZ(50000000), .SAMPLE_RATE_HZ(48000)) u_b (
        .clk_in(sys_clk), .rst_n(sys_rst_n), .audio_enable(sounding),
        .sample_data(sample_data), .sample_valid(sample_valid), .audio_ready(audio_ready),
        .sample_request(sample_request), .sample_underrun(sample_underrun),
        .i2s_bclk(HP_BCK), .i2s_lrclk(HP_WS), .i2s_sdata(HP_DIN), .pa_en(PA_EN)
    );
endmodule

module instrument_adsr_auto_top (
    input wire sys_clk, input wire sys_rst_n, input wire [1:0] Key_in,
    output wire HP_BCK, output wire HP_WS, output wire HP_DIN, output wire PA_EN
);
    instrument_adsr_top #(.AUTO_TEST(1)) u_demo (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .Key_in(Key_in),
        .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN), .PA_EN(PA_EN)
    );
endmodule
