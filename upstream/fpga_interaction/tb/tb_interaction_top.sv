`timescale 1ns/1ps

module tb_interaction_top;
    reg clk;
    reg rst_n;
    reg [12:0] key_n;
    reg [90:0] key_velocity_flat;
    reg timbre_key_n;
    reg pressure_valid;
    reg [23:0] knob_raw_flat;
    reg knob_valid;
    reg [11:0] pressure_raw;
    reg [31:0] release_done;
    reg expr_valid;
    reg [4:0] expr_source_id;
    reg [6:0] expr_note;
    reg [15:0] expr_pitch_bend;
    reg [7:0] expr_aftertouch;
    reg [7:0] expr_vibrato_depth;
    reg [7:0] expr_vibrato_rate;
    reg test_enable;
    reg test_clear;
    reg [5:0] test_voices;
    wire [12:0] key_level;
    wire [12:0] key_press;
    wire [12:0] key_release;
    wire [3:0] timbre_id;
    wire timbre_press;
    wire [13:0] knob_value_flat;
    wire knob_param_valid;
    wire param_ready;
    wire param_fault;
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

    always #5 clk = ~clk;

    interaction_top #(
        .KEY_COUNT        (13),
        .VOICES           (32),
        .ACTIVE_LOW       (1),
        .DEBOUNCE_CYCLES  (4),
        .MAX_EVENTS       (64),
        .FIFO_PTR_WIDTH   (6),
        .SOURCE_WIDTH     (5),
        .TEST_HOLD_CYCLES (20)
    ) dut (
        .octave_select(2'd1),
        .sustain_on(1'b0),
        .source_clear_valid(1'b0),
        .source_clear_id(5'd0),
        .source_clear_mask(5'd0),
        .source_clear_ready(),
        .voice_key_down(),
        .voice_trigger_id_flat(),
        .input_fault(),
        .release_trigger_id_flat(512'd0),
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
        .key_level(key_level),
        .key_press(key_press),
        .key_release(key_release),
        .timbre_id(timbre_id),
        .timbre_press(timbre_press),
        .knob_value_flat(knob_value_flat),
        .knob_param_valid(knob_param_valid),
        .param_ready(param_ready),
        .param_fault(param_fault),
        .pressure_velocity(pressure_velocity),
        .pressure_active(pressure_active),
        .event_valid(event_valid),
        .event_type(event_type),
        .event_source_id(event_source_id),
        .event_note(event_note),
        .event_velocity(event_velocity),
        .event_timbre(event_timbre),
        .expr_ready(expr_ready),
        .test_busy(test_busy),
        .test_done(test_done),
        .voice_active(voice_active),
        .voice_gate(voice_gate),
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

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        key_n = 13'h1FFF;
        key_velocity_flat = {13{7'd100}};
        timbre_key_n = 1'b1;
        pressure_valid = 1'b0;
        knob_raw_flat = 24'd0;
        knob_valid = 1'b1;
        pressure_raw = 12'd0;
        release_done = 32'hFFFFFFFF;
        expr_valid = 1'b0;
        expr_source_id = 5'd0;
        expr_note = 7'd0;
        expr_pitch_bend = 16'd0;
        expr_aftertouch = 8'd0;
        expr_vibrato_depth = 8'd0;
        expr_vibrato_rate = 8'd0;
        test_enable = 1'b0;
        test_clear = 1'b0;
        test_voices = 6'd32;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        @(negedge clk);
        key_n[0] = 1'b0;
        repeat (120) @(posedge clk);

        if (key_level[0] !== 1'b1) begin
            $display("FAIL: key0 should be pressed");
            $finish;
        end
        if (!voice_active[0]) begin
            $display("FAIL: voice0 should be allocated for key0");
            $finish;
        end
        if (dut.u_voice_allocator.source_id_mem[0] != 5'd0) begin
            $display("FAIL: voice0 source_id should be 0");
            $finish;
        end

        @(negedge clk);
        key_n[0] = 1'b1;
        repeat (120) @(posedge clk);

        if (key_level[0] !== 1'b0) begin
            $display("FAIL: key0 should be released");
            $finish;
        end
        if (voice_active[0]) begin
            $display("FAIL: voice0 should be released after key0 release");
            $finish;
        end

        $display("PASS: tb_interaction_top_32key key/LED path and voice allocation");
        $finish;
    end
endmodule