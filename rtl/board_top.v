`timescale 1ns/1ps

module board_top #(
    parameter integer DEBOUNCE_CYCLES  = 250000,
    parameter integer LED_ACTIVE_LOW   = 0,
    parameter integer TEST_MODE        = 0,
    parameter integer TEST_VOICES      = 32,
    parameter integer TEST_HOLD_CYCLES = 50000000
) (
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire [1:0] Key_in,
    output wire [3:0] LEDs
);

    localparam [13:0] DEFAULT_KEY_VELOCITY = {7'd100, 7'd100};
    localparam [5:0] TEST_VOICES_VALUE = TEST_VOICES;

    wire rst_n_sync;
    wire [1:0] key_level;
    wire [1:0] key_press;
    wire [1:0] key_release;
    wire [6:0] pressure_velocity;
    wire pressure_active;
    wire event_valid;
    wire event_type;
    wire [4:0] event_source_id;
    wire [6:0] event_note;
    wire [6:0] event_velocity;
    wire [3:0] event_timbre;
    wire expr_ready;
    wire test_busy;
    wire test_done;
    wire [31:0] voice_active;
    wire [31:0] voice_gate;
    wire [159:0] voice_source_id_flat;
    wire [223:0] voice_note_flat;
    wire [223:0] voice_velocity_flat;
    wire [127:0] voice_timbre_flat;
    wire [511:0] voice_pitch_bend_flat;
    wire [255:0] voice_aftertouch_flat;
    wire [255:0] voice_vibrato_depth_flat;
    wire [255:0] voice_vibrato_rate_flat;
    wire [5:0] voice_count;
    wire [5:0] max_voice_count;
    wire [31:0] note_on_count;
    wire [31:0] note_off_count;
    wire [31:0] steal_count;
    wire steal_pulse;
    wire [3:0] led_value;

    reset_sync u_reset_sync (
        .clk         (sys_clk),
        .raw_rst_n   (sys_rst_n),
        .rst_n_sync  (rst_n_sync)
    );

    interaction_top #(
        .KEY_COUNT        (2),
        .VOICES           (32),
        .ACTIVE_LOW       (1),
        .DEBOUNCE_CYCLES  (DEBOUNCE_CYCLES),
        .MAX_EVENTS       (64),
        .FIFO_PTR_WIDTH   (6),
        .SOURCE_WIDTH     (5),
        .TEST_HOLD_CYCLES (TEST_HOLD_CYCLES)
    ) u_interaction_top (
        .clk                      (sys_clk),
        .rst_n                    (rst_n_sync),
        .key_n                    (Key_in),
        .key_velocity_flat        (DEFAULT_KEY_VELOCITY),
        .pressure_valid           (1'b0),
        .pressure_raw             (12'd0),
        .release_done             (32'hFFFFFFFF),
        .expr_valid               (1'b0),
        .expr_source_id           (5'd0),
        .expr_note                (7'd0),
        .expr_pitch_bend          (16'd0),
        .expr_aftertouch          (8'd0),
        .expr_vibrato_depth       (8'd0),
        .expr_vibrato_rate        (8'd0),
        .test_enable              (TEST_MODE != 0),
        .test_clear               (1'b0),
        .test_voices              (TEST_VOICES_VALUE),
        .key_level                (key_level),
        .key_press                (key_press),
        .key_release              (key_release),
        .pressure_velocity        (pressure_velocity),
        .pressure_active          (pressure_active),
        .event_valid              (event_valid),
        .event_type               (event_type),
        .event_source_id          (event_source_id),
        .event_note               (event_note),
        .event_velocity           (event_velocity),
        .event_timbre             (event_timbre),
        .expr_ready               (expr_ready),
        .test_busy                (test_busy),

        .test_done                (test_done),
        .voice_active             (voice_active),
        .voice_gate               (voice_gate),
        .voice_source_id_flat     (voice_source_id_flat),
        .voice_note_flat          (voice_note_flat),
        .voice_velocity_flat      (voice_velocity_flat),
        .voice_timbre_flat        (voice_timbre_flat),
        .voice_pitch_bend_flat    (voice_pitch_bend_flat),
        .voice_aftertouch_flat    (voice_aftertouch_flat),
        .voice_vibrato_depth_flat (voice_vibrato_depth_flat),
        .voice_vibrato_rate_flat  (voice_vibrato_rate_flat),
        .voice_count              (voice_count),
        .max_voice_count          (max_voice_count),
        .note_on_count            (note_on_count),
        .note_off_count           (note_off_count),
        .steal_count              (steal_count),
        .steal_pulse              (steal_pulse)
    );

    assign led_value[0] = key_level[0];
    assign led_value[1] = key_level[1];
    assign led_value[2] = (voice_count != 6'd0);
    assign led_value[3] = (max_voice_count >= 6'd4);
    assign LEDs = LED_ACTIVE_LOW ? ~led_value : led_value;

endmodule