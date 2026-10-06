// Tang Mega 60K NEO Dock 31004 板级 demo。
// V22=50 MHz；AA13=KEY0 复位；AB13=KEY1(C4)，Y12=KEY2(E4)。
// 原理图编号对应 KEY0=S4、KEY1=S2、KEY2=S1；只统一名称，不改引脚。
// 所有处理共享 sys_clk；按键由 C 的两级同步/消抖模块接收。
module instrument_demo_top #(
    parameter integer AUTO_TEST = 0,
    parameter integer DEBOUNCE_CYCLES = 250000,
    parameter integer TEST_HOLD_CYCLES = 50000000
) (
    input wire sys_clk,
    input wire sys_rst_n, // 板上 KEY0，按下为 0。
    input wire [1:0] Key_in, // [0]=板上 KEY1，[1]=板上 KEY2；不是 KEY0/KEY1。
    output wire HP_BCK,
    output wire HP_WS,
    output wire HP_DIN,
    output wire PA_EN
);
    wire audio_ready, sample_request, sample_underrun;
    wire [3:0] voice_gate, voice_active, release_done;
    wire [27:0] voice_note_flat, voice_velocity_flat;
    wire [5:0] voice_count;
    wire signed [15:0] sample_data;
    wire sample_valid, sounding;
    // B 内部复位异步断言、两拍同步释放；A/C 使用同一个已同步复位。
    // 没有传感器时只接两键固定力度，不宣称压力输入/表情参数已接入。
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
        .voice_active(voice_active), .voice_gate(voice_gate),
        .voice_note_flat(voice_note_flat), .voice_velocity_flat(voice_velocity_flat),
        .voice_count(voice_count),
        // 明确留空的调试/尚未接入功能，避免被误认为漏接输入。
        .key_level(), .key_press(), .key_release(),
        .pressure_velocity(), .pressure_active(),
        .event_valid(), .event_type(), .event_source_id(),
        .event_note(), .event_velocity(), .event_timbre(), .expr_ready(),
        .test_busy(), .test_done(), .voice_source_id_flat(), .voice_timbre_flat(),
        .voice_pitch_bend_flat(), .voice_aftertouch_flat(),
        .voice_vibrato_depth_flat(), .voice_vibrato_rate_flat(),
        .max_voice_count(), .note_on_count(), .note_off_count(), .steal_count(), .steal_pulse(),
        .voice_trigger() // 旧渐变 demo 保持不变；新 ADSR 顶层接入此信号。
    );
    demo_voice_bank u_bank (
        .clk(sys_clk), .rst_n(audio_ready), .sample_request(sample_request),
        .voice_gate(voice_gate), .voice_note_flat(voice_note_flat),
        .voice_velocity_flat(voice_velocity_flat), .release_done(release_done),
        .sounding(sounding), .sample_data(sample_data), .sample_valid(sample_valid)
    );
    synth_top #(.AUDIO_CLK_HZ(50000000), .SAMPLE_RATE_HZ(48000)) u_b (
        .clk_in(sys_clk), .rst_n(sys_rst_n), .audio_enable(sounding),
        .sample_data(sample_data), .sample_valid(sample_valid),
        .audio_ready(audio_ready), .sample_request(sample_request),
        .sample_underrun(sample_underrun),
        .i2s_bclk(HP_BCK), .i2s_lrclk(HP_WS), .i2s_sdata(HP_DIN), .pa_en(PA_EN)
    );
endmodule

// 无额外外设的四声部试听：上电复位/按 KEY0 后启动一次，约 1 秒后释放。
// 硬件实测前不宣称实际音质或复音验收已通过。
module instrument_demo_auto_top (
    input wire sys_clk,
    input wire sys_rst_n,
    input wire [1:0] Key_in,
    output wire HP_BCK,
    output wire HP_WS,
    output wire HP_DIN,
    output wire PA_EN
);
    instrument_demo_top #(.AUTO_TEST(1)) u_demo (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .Key_in(Key_in),
        .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN), .PA_EN(PA_EN)
    );
endmodule
