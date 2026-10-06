`timescale 1ns/1ps

module interaction_top #(
    parameter integer KEY_COUNT       = 2,
    parameter integer VOICES          = 32,
    parameter integer ACTIVE_LOW      = 1,
    parameter integer DEBOUNCE_CYCLES = 250000,
    parameter integer MAX_EVENTS      = 64,
    parameter integer FIFO_PTR_WIDTH  = 6,
    parameter integer SOURCE_WIDTH    = 5,
    parameter integer TEST_HOLD_CYCLES = 50000000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [KEY_COUNT-1:0] key_n,
    input  wire [KEY_COUNT*7-1:0] key_velocity_flat,
    input  wire pressure_valid,
    input  wire [11:0] pressure_raw,
    input  wire [VOICES-1:0] release_done,
    input  wire expr_valid,
    input  wire [SOURCE_WIDTH-1:0] expr_source_id,
    input  wire [6:0] expr_note,
    input  wire [15:0] expr_pitch_bend,
    input  wire [7:0] expr_aftertouch,
    input  wire [7:0] expr_vibrato_depth,
    input  wire [7:0] expr_vibrato_rate,
    input  wire test_enable,
    input  wire test_clear,
    input  wire [5:0] test_voices,
    output wire [KEY_COUNT-1:0] key_level,
    output wire [KEY_COUNT-1:0] key_press,
    output wire [KEY_COUNT-1:0] key_release,
    output wire [6:0] pressure_velocity,
    output wire pressure_active,
    output wire event_valid,
    output wire event_type,
    output wire [SOURCE_WIDTH-1:0] event_source_id,
    output wire [6:0] event_note,
    output wire [6:0] event_velocity,
    output wire [3:0] event_timbre,
    output wire expr_ready,
    output wire test_busy,
    output wire test_done,
    output wire [VOICES-1:0] voice_active,
    output wire [VOICES-1:0] voice_gate,
    output wire [VOICES*SOURCE_WIDTH-1:0] voice_source_id_flat,
    output wire [VOICES*7-1:0] voice_note_flat,
    output wire [VOICES*7-1:0] voice_velocity_flat,
    output wire [VOICES*4-1:0] voice_timbre_flat,
    output wire [VOICES*16-1:0] voice_pitch_bend_flat,
    output wire [VOICES*8-1:0] voice_aftertouch_flat,
    output wire [VOICES*8-1:0] voice_vibrato_depth_flat,
    output wire [VOICES*8-1:0] voice_vibrato_rate_flat,
    output wire [5:0] voice_count,
    output wire [5:0] max_voice_count,
    output wire [31:0] note_on_count,
    output wire [31:0] note_off_count,
    output wire [31:0] steal_count,
    output wire steal_pulse,
    output wire [VOICES-1:0] voice_trigger
);

    wire event_ready_alloc;
    wire normal_event_ready;
    wire test_event_ready;
    wire test_select;
    wire normal_event_valid;
    wire normal_event_type;
    wire [SOURCE_WIDTH-1:0] normal_event_source_id;
    wire [6:0] normal_event_note;
    wire [6:0] normal_event_velocity;
    wire [3:0] normal_event_timbre;
    wire test_event_valid;
    wire test_event_type;
    wire [SOURCE_WIDTH-1:0] test_source_id;
    wire [6:0] test_note;
    wire [6:0] test_velocity;
    wire [3:0] test_timbre;
    wire [6:0] default_pressure_velocity;

    assign test_select = test_enable | test_busy;
    assign normal_event_ready = event_ready_alloc && !test_select;
    assign test_event_ready = event_ready_alloc && test_select;

    assign event_valid    = test_select ? test_event_valid : normal_event_valid;
    assign event_type     = test_select ? test_event_type : normal_event_type;
    assign event_source_id = test_select ? test_source_id : normal_event_source_id;
    assign event_note     = test_select ? test_note : normal_event_note;
    assign event_velocity = test_select ? test_velocity : normal_event_velocity;
    assign event_timbre   = test_select ? test_timbre : normal_event_timbre;

    touch_or_key_if #(
        .KEY_COUNT       (KEY_COUNT),
        .ACTIVE_LOW      (ACTIVE_LOW),
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES)
    ) u_key_if (
        .clk         (clk),
        .rst_n       (rst_n),
        .raw_key     (key_n),
        .key_level   (key_level),
        .key_press   (key_press),
        .key_release (key_release)
    );

    pressure_if u_pressure_if (
        .clk               (clk),
        .rst_n             (rst_n),
        .sample_valid      (pressure_valid),
        .pressure_raw      (pressure_raw),
        .pressure_filtered (),
        .velocity          (pressure_velocity),
        .pressure_active   (pressure_active)
    );

    event_encoder #(
        .KEY_COUNT    (KEY_COUNT),
        .MAX_EVENTS   (MAX_EVENTS),
        .PTR_WIDTH    (FIFO_PTR_WIDTH),
        .SOURCE_WIDTH (SOURCE_WIDTH)
    ) u_event_encoder (
        .clk                (clk),
        .rst_n              (rst_n),
        .key_press          (key_press),
        .key_release        (key_release),
        .key_velocity_flat  (key_velocity_flat),
        .input_timbre       (4'd0),
        .event_valid        (normal_event_valid),
        .event_type         (normal_event_type),
        .event_source_id    (normal_event_source_id),
        .event_note         (normal_event_note),
        .event_velocity     (normal_event_velocity),
        .event_timbre       (normal_event_timbre),
        .event_ready        (normal_event_ready)
    );

    voice_test_pattern #(
        .SOURCE_WIDTH (SOURCE_WIDTH),
        .NOTE_BASE    (36),
        .HOLD_CYCLES  (TEST_HOLD_CYCLES)
    ) u_voice_test_pattern (
        .clk              (clk),
        .rst_n            (rst_n),
        .test_enable      (test_enable),
        .test_clear       (test_clear),
        .test_voices      (test_voices),
        .test_event_valid (test_event_valid),
        .test_event_ready (test_event_ready),
        .test_event_type  (test_event_type),
        .test_source_id   (test_source_id),
        .test_note        (test_note),
        .test_velocity    (test_velocity),
        .test_timbre      (test_timbre),
        .test_busy        (test_busy),
        .test_done        (test_done)
    );

    voice_allocator #(
        .VOICES       (VOICES),
        .IDX_WIDTH    (5),
        .COUNT_WIDTH  (6),
        .TIME_WIDTH   (32),
        .SOURCE_WIDTH (SOURCE_WIDTH),
        .BEND_WIDTH   (16),
        .EXPR_WIDTH   (8)
    ) u_voice_allocator (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .event_valid             (event_valid),
        .event_ready             (event_ready_alloc),
        .event_type              (event_type),
        .event_source_id         (event_source_id),
        .event_note              (event_note),
        .event_velocity          (event_velocity),
        .event_timbre            (event_timbre),
        .expr_valid              (expr_valid),
        .expr_ready              (expr_ready),
        .expr_source_id          (expr_source_id),
        .expr_note               (expr_note),
        .expr_pitch_bend         (expr_pitch_bend),
        .expr_aftertouch         (expr_aftertouch),
        .expr_vibrato_depth      (expr_vibrato_depth),
        .expr_vibrato_rate       (expr_vibrato_rate),
        .release_done            (release_done),
        .voice_active            (voice_active),
        .voice_gate              (voice_gate),
        .voice_source_id_flat    (voice_source_id_flat),
        .voice_note_flat         (voice_note_flat),
        .voice_velocity_flat     (voice_velocity_flat),
        .voice_timbre_flat       (voice_timbre_flat),
        .voice_pitch_bend_flat   (voice_pitch_bend_flat),
        .voice_aftertouch_flat   (voice_aftertouch_flat),
        .voice_vibrato_depth_flat(voice_vibrato_depth_flat),
        .voice_vibrato_rate_flat (voice_vibrato_rate_flat),
        .voice_count             (voice_count),
        .max_voice_count         (max_voice_count),
        .note_on_count           (note_on_count),
        .note_off_count          (note_off_count),
        .steal_count             (steal_count),
        .steal_pulse             (steal_pulse),
        .voice_trigger           (voice_trigger)
    );

endmodule
