`timescale 1ns/1ps

module interaction_top #(
    parameter integer KEY_COUNT        = 13,
    parameter integer VOICES           = 32,
    parameter integer ACTIVE_LOW       = 1,
    parameter integer DEBOUNCE_CYCLES  = 100000, // 2 ms at 50 MHz
    parameter integer MAX_EVENTS       = 64,
    parameter integer FIFO_PTR_WIDTH   = 6,
    parameter integer SOURCE_WIDTH     = 5,
    parameter integer NOTE_BASE        = 60,
    parameter integer TIMBRE_COUNT     = 8,
    parameter integer KNOB_COUNT       = 2,
    parameter integer ADC_WIDTH        = 12,
    parameter integer TEST_HOLD_CYCLES = 50000000,
    parameter integer CHECK_RELEASE_ID = 0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [KEY_COUNT-1:0] key_n,
    input  wire [KEY_COUNT*7-1:0] key_velocity_flat,
    input  wire [1:0] octave_select,
    input  wire sustain_on,
    input  wire source_clear_valid,
    input  wire [SOURCE_WIDTH-1:0] source_clear_id,
    input  wire [SOURCE_WIDTH-1:0] source_clear_mask,
    output wire source_clear_ready,
    input  wire timbre_key_n,
    input  wire pressure_valid,
    input  wire [11:0] pressure_raw,
    input  wire [KNOB_COUNT*ADC_WIDTH-1:0] knob_raw_flat,
    input  wire knob_valid,
    input  wire [VOICES-1:0] release_done,
    input  wire [VOICES*16-1:0] release_trigger_id_flat,
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
    output wire [3:0] timbre_id,
    output wire timbre_press,
    output wire [KNOB_COUNT*7-1:0] knob_value_flat,
    output wire knob_param_valid,
    output wire param_ready,
    output wire param_fault,
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
    output wire [VOICES-1:0] voice_key_down,
    output wire [VOICES*16-1:0] voice_trigger_id_flat,
    output wire input_fault,
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
    output wire steal_pulse
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
    wire timbre_level;
    wire timbre_release;
    reg  [3:0] timbre_id_reg;
    reg encoder_clear_sent;
    wire allocator_clear_ready;
    wire encoder_clear_pending = input_fault && !encoder_clear_sent;
    wire allocator_clear_valid = encoder_clear_pending || source_clear_valid;
    wire [SOURCE_WIDTH-1:0] allocator_clear_id = encoder_clear_pending ? {SOURCE_WIDTH{1'b0}} : source_clear_id;
    localparam [SOURCE_WIDTH-1:0] LOCAL_GROUP_MASK = {1'b1, {(SOURCE_WIDTH-1){1'b0}}};
    wire [SOURCE_WIDTH-1:0] allocator_clear_mask = encoder_clear_pending ? LOCAL_GROUP_MASK : source_clear_mask;
    assign source_clear_ready = allocator_clear_ready && !encoder_clear_pending;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) encoder_clear_sent <= 1'b0;
        else if (!input_fault) encoder_clear_sent <= 1'b0;
        else if (encoder_clear_pending && allocator_clear_ready) encoder_clear_sent <= 1'b1;
    end

    assign timbre_id = timbre_id_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timbre_id_reg <= 4'd0;
        end else if (timbre_press) begin
            if (timbre_id_reg >= (TIMBRE_COUNT - 1)) begin
                timbre_id_reg <= 4'd0;
            end else begin
                timbre_id_reg <= timbre_id_reg + 1'b1;
            end
        end
    end
    assign test_select = test_enable | test_busy;
    assign normal_event_ready = event_ready_alloc && !test_select && !input_fault;
    assign test_event_ready = event_ready_alloc && test_select;

    assign event_valid     = test_select ? test_event_valid : (normal_event_valid && !input_fault);
    assign event_type      = test_select ? test_event_type : normal_event_type;
    assign event_source_id = test_select ? test_source_id : normal_event_source_id;
    assign event_note      = test_select ? test_note : normal_event_note;
    assign event_velocity  = test_select ? test_velocity : normal_event_velocity;
    assign event_timbre    = test_select ? test_timbre : normal_event_timbre;

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

    input_sync_debounce #(
        .ACTIVE_LOW      (ACTIVE_LOW),
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES)
    ) u_timbre_key (
        .clk           (clk),
        .rst_n         (rst_n),
        .async_in      (timbre_key_n),
        .level         (timbre_level),
        .press_pulse   (timbre_press),
        .release_pulse (timbre_release)
    );

    adc_knob_if #(
        .ADC_WIDTH     (ADC_WIDTH),
        .KNOB_COUNT    (KNOB_COUNT),
        .READY_SAMPLES (16)
    ) u_adc_knob_if (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_valid    (knob_valid),
        .raw_flat        (knob_raw_flat),
        .value_flat      (knob_value_flat),
        .param_valid     (knob_param_valid),
        .ready           (param_ready),
        .fault           (param_fault)
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
        .NOTE_BASE    (NOTE_BASE),
        .MAX_EVENTS   (MAX_EVENTS),
        .PTR_WIDTH    (FIFO_PTR_WIDTH),
        .SOURCE_WIDTH (SOURCE_WIDTH)
    ) u_event_encoder (
        .clk                (clk),
        .rst_n              (rst_n),
        .key_press          (key_press),
        .key_release        (key_release),
        .key_velocity_flat  (key_velocity_flat),
        .input_timbre       (timbre_id),
        .octave_select      (octave_select),
        .input_overflow     (input_fault),
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
        .EXPR_WIDTH   (8),
        .CHECK_RELEASE_ID (CHECK_RELEASE_ID)
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
        .sustain_on              (sustain_on),
        .source_clear_valid      (allocator_clear_valid),
        .source_clear_ready      (allocator_clear_ready),
        .source_clear_id         (allocator_clear_id),
        .source_clear_mask       (allocator_clear_mask),
        .expr_valid              (expr_valid),
        .expr_ready              (expr_ready),
        .expr_source_id          (expr_source_id),
        .expr_note               (expr_note),
        .expr_pitch_bend         (expr_pitch_bend),
        .expr_aftertouch         (expr_aftertouch),
        .expr_vibrato_depth      (expr_vibrato_depth),
        .expr_vibrato_rate       (expr_vibrato_rate),
        .release_done            (release_done),
        .release_trigger_id_flat (release_trigger_id_flat),
        .voice_active            (voice_active),
        .voice_gate              (voice_gate),
        .voice_key_down          (voice_key_down),
        .voice_trigger_id_flat   (voice_trigger_id_flat),
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
        .steal_pulse             (steal_pulse)
    );

endmodule
