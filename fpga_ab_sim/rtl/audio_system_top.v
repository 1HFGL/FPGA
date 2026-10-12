`timescale 1ns/1ps

module audio_system_top #(
    parameter integer KEY_COUNT        = 13,
    parameter integer VOICES           = 32,
    parameter integer CLK_HZ           = 50000000,
    parameter integer SAMPLE_RATE      = 48000,
    parameter integer I2S_BCLK_DIV     = 4,
    parameter integer DEBOUNCE_CYCLES  = 250000, // 5 ms at 50 MHz
    parameter integer TEST_HOLD_CYCLES = 50000000,
    parameter integer MAX_EVENTS       = 64
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [KEY_COUNT-1:0] key_n,
    input  wire [KEY_COUNT*7-1:0] key_velocity_flat,
    input  wire timbre_key_n,
    input  wire pressure_valid,
    input  wire [11:0] pressure_raw,
    input  wire [23:0] knob_raw_flat,
    input  wire knob_valid,
    input  wire expr_valid,
    input  wire [4:0] expr_source_id,
    input  wire [6:0] expr_note,
    input  wire [15:0] expr_pitch_bend,
    input  wire [7:0] expr_aftertouch,
    input  wire [7:0] expr_vibrato_depth,
    input  wire [7:0] expr_vibrato_rate,
    input  wire test_enable,
    input  wire test_clear,
    input  wire [5:0] test_voices,
    output wire sample_tick,
    output wire signed [15:0] audio_sample,
    output wire i2s_bclk,
    output wire i2s_lrck,
    output wire i2s_sdata,
    output wire [VOICES-1:0] voice_active,
    output wire [VOICES-1:0] voice_gate,
    output wire [3:0] timbre_id,
    output wire [13:0] knob_value_flat,
    output wire param_ready,
    output wire param_fault,
    output wire [5:0] voice_count,
    output wire [5:0] max_voice_count,
    output wire [VOICES-1:0] release_done,
    output wire test_busy,
    output wire test_done
);

    wire [VOICES-1:0] voice_active_c;
    wire [VOICES-1:0] voice_gate_c;
    wire [VOICES*5-1:0] voice_source_id_flat;
    wire [VOICES*7-1:0] voice_note_flat;
    wire [VOICES*7-1:0] voice_velocity_flat;
    wire [VOICES*4-1:0] voice_timbre_flat;
    wire [VOICES*16-1:0] voice_pitch_bend_flat;
    wire [VOICES*8-1:0] voice_aftertouch_flat;
    wire [VOICES*8-1:0] voice_vibrato_depth_flat;
    wire [VOICES*8-1:0] voice_vibrato_rate_flat;
    wire [VOICES*16-1:0] voice_sample_flat;
    wire [31:0] note_on_count;
    wire [31:0] note_off_count;
    wire [31:0] steal_count;
    wire steal_pulse;
    wire expr_ready;
    wire event_valid;
    wire event_type;
    wire [4:0] event_source_id;
    wire [6:0] event_note;
    wire [6:0] event_velocity;
    wire [3:0] event_timbre;
    wire timbre_press;
    wire knob_param_valid;
    wire [6:0] master_volume;
    wire [6:0] tone_brightness;

    assign voice_active = voice_active_c;
    assign master_volume = param_ready ? knob_value_flat[6:0] : 7'd127;
    assign tone_brightness = param_ready ? knob_value_flat[13:7] : 7'd127;
    assign voice_gate = voice_gate_c;

    sample_tick_gen #(
        .CLK_HZ      (CLK_HZ),
        .SAMPLE_RATE (SAMPLE_RATE)
    ) u_sample_tick_gen (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_tick (sample_tick)
    );

    interaction_top #(
        .KEY_COUNT       (KEY_COUNT),
        .VOICES          (VOICES),
        .ACTIVE_LOW      (1),
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES),
        .MAX_EVENTS      (MAX_EVENTS),
        .FIFO_PTR_WIDTH  (6),
        .SOURCE_WIDTH    (5),
        .NOTE_BASE       (60),
        .TIMBRE_COUNT    (8),
        .KNOB_COUNT      (2),
        .ADC_WIDTH       (12),
        .TEST_HOLD_CYCLES(TEST_HOLD_CYCLES)
    ) u_interaction_top (
        .clk(clk),
        .rst_n(rst_n),
        .key_n(key_n),
        .key_velocity_flat(key_velocity_flat),
        .timbre_key_n(timbre_key_n),
        .pressure_valid(pressure_valid),
        .pressure_raw(pressure_raw),
        .knob_raw_flat(knob_raw_flat),
        .knob_valid(knob_valid),
        .release_done(release_done),
        .expr_valid(expr_valid),
        .expr_source_id(expr_source_id),
        .expr_note(expr_note),
        .expr_pitch_bend(expr_pitch_bend),
        .expr_aftertouch(expr_aftertouch),
        .expr_vibrato_depth(expr_vibrato_depth),
        .expr_vibrato_rate(expr_vibrato_rate),
        .test_enable(test_enable),
        .test_clear(test_clear),
        .test_voices(test_voices),
        .key_level(),
        .key_press(),
        .key_release(),
        .timbre_id(timbre_id),
        .timbre_press(timbre_press),
        .knob_value_flat(knob_value_flat),
        .knob_param_valid(knob_param_valid),
        .param_ready(param_ready),
        .param_fault(param_fault),
        .pressure_velocity(),
        .pressure_active(),
        .event_valid(event_valid),
        .event_type(event_type),
        .event_source_id(event_source_id),
        .event_note(event_note),
        .event_velocity(event_velocity),
        .event_timbre(event_timbre),
        .expr_ready(expr_ready),
        .test_busy(test_busy),
        .test_done(test_done),
        .voice_active(voice_active_c),
        .voice_gate(voice_gate_c),
        .voice_source_id_flat(voice_source_id_flat),
        .voice_note_flat(voice_note_flat),
        .voice_velocity_flat(voice_velocity_flat),
        .voice_timbre_flat(voice_timbre_flat),
        .voice_pitch_bend_flat(voice_pitch_bend_flat),
        .voice_aftertouch_flat(voice_aftertouch_flat),
        .voice_vibrato_depth_flat(voice_vibrato_depth_flat),
        .voice_vibrato_rate_flat(voice_vibrato_rate_flat),
        .voice_count(voice_count),
        .max_voice_count(max_voice_count),
        .note_on_count(note_on_count),
        .note_off_count(note_off_count),
        .steal_count(steal_count),
        .steal_pulse(steal_pulse)
    );

    synth_engine #(
        .VOICES (VOICES)
    ) u_synth_engine (
        .clk(clk),
        .rst_n(rst_n),
        .sample_tick(sample_tick),
        .voice_active(voice_active_c),
        .voice_gate(voice_gate_c),
        .voice_note_flat(voice_note_flat),
        .voice_velocity_flat(voice_velocity_flat),
        .voice_timbre_flat(voice_timbre_flat),
        .voice_pitch_bend_flat(voice_pitch_bend_flat),
        .master_volume(master_volume),
        .tone_brightness(tone_brightness),
        .release_done(release_done),
        .voice_sample_flat(voice_sample_flat),
        .audio_sample(audio_sample)
    );

    i2s_tx #(
        .BCLK_DIV (I2S_BCLK_DIV)
    ) u_i2s_tx (
        .clk(clk),
        .rst_n(rst_n),
        .sample_tick(sample_tick),
        .sample_in(audio_sample),
        .bclk(i2s_bclk),
        .lrck(i2s_lrck),
        .sdata(i2s_sdata)
    );

endmodule
