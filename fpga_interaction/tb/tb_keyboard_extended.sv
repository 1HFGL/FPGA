`timescale 1ns/1ps

module tb_keyboard_extended;
    reg clk;
    reg rst_n;
    reg [12:0] key_n;
    reg [90:0] key_velocity_flat;
    reg timbre_key_n;
    reg [23:0] knob_raw_flat;
    reg knob_valid;
    reg [31:0] release_done;
    wire [12:0] key_level;
    wire [12:0] key_press;
    wire [12:0] key_release;
    wire [3:0] timbre_id;
    wire timbre_press;
    wire [13:0] knob_value_flat;
    wire knob_param_valid;
    wire param_ready;
    wire param_fault;
    wire [31:0] voice_active;
    wire [31:0] voice_gate;
    wire [223:0] voice_note_flat;
    wire [5:0] voice_count;
    wire [5:0] max_voice_count;
    integer i;
    reg found60;
    reg found72;

    always #5 clk = ~clk;

    interaction_top #(
        .KEY_COUNT        (13),
        .VOICES           (32),
        .ACTIVE_LOW       (1),
        .DEBOUNCE_CYCLES  (4),
        .MAX_EVENTS       (64),
        .FIFO_PTR_WIDTH   (6),
        .SOURCE_WIDTH     (5),
        .NOTE_BASE        (60),
        .TIMBRE_COUNT     (8),
        .KNOB_COUNT       (2),
        .ADC_WIDTH        (12),
        .TEST_HOLD_CYCLES (20)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .key_n(key_n),
        .key_velocity_flat(key_velocity_flat),
        .timbre_key_n(timbre_key_n),
        .pressure_valid(1'b0),
        .pressure_raw(12'd0),
        .knob_raw_flat(knob_raw_flat),
        .knob_valid(knob_valid),
        .release_done(release_done),
        .expr_valid(1'b0),
        .expr_source_id(5'd0),
        .expr_note(7'd0),
        .expr_pitch_bend(16'd0),
        .expr_aftertouch(8'd0),
        .expr_vibrato_depth(8'd0),
        .expr_vibrato_rate(8'd0),
        .test_enable(1'b0),
        .test_clear(1'b0),
        .test_voices(6'd0),
        .key_level(key_level),
        .key_press(key_press),
        .key_release(key_release),
        .timbre_id(timbre_id),
        .timbre_press(timbre_press),
        .knob_value_flat(knob_value_flat),
        .knob_param_valid(knob_param_valid),
        .param_ready(param_ready),
        .param_fault(param_fault),
        .pressure_velocity(),
        .pressure_active(),
        .event_valid(),
        .event_type(),
        .event_source_id(),
        .event_note(),
        .event_velocity(),
        .event_timbre(),
        .expr_ready(),
        .test_busy(),
        .test_done(),
        .voice_active(voice_active),
        .voice_gate(voice_gate),
        .voice_source_id_flat(),
        .voice_note_flat(voice_note_flat),
        .voice_velocity_flat(),
        .voice_timbre_flat(),
        .voice_pitch_bend_flat(),
        .voice_aftertouch_flat(),
        .voice_vibrato_depth_flat(),
        .voice_vibrato_rate_flat(),
        .voice_count(voice_count),
        .max_voice_count(max_voice_count),
        .note_on_count(),
        .note_off_count(),
        .steal_count(),
        .steal_pulse()
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        key_n = 13'h1FFF;
        key_velocity_flat = {13{7'd100}};
        timbre_key_n = 1'b1;
        knob_raw_flat = 24'd0;
        knob_valid = 1'b1;
        release_done = 32'hFFFFFFFF;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        @(negedge clk);
        key_n[0] = 1'b0;
        key_n[12] = 1'b0;
        repeat (160) @(posedge clk);

        if (voice_count < 6'd2) begin
            $display("FAIL: expected at least 2 voices, got %0d", voice_count);
            $finish;
        end

        found60 = 1'b0;
        found72 = 1'b0;
        for (i = 0; i < 32; i = i + 1) begin
            if (voice_active[i] && (voice_note_flat[i*7 +: 7] == 7'd60)) found60 = 1'b1;
            if (voice_active[i] && (voice_note_flat[i*7 +: 7] == 7'd72)) found72 = 1'b1;
        end
        if (!found60 || !found72) begin
            $display("FAIL: note mapping expected 60 and 72, got n60=%0b n72=%0b", found60, found72);
            $finish;
        end

        @(negedge clk);
        key_n[0] = 1'b1;
        key_n[12] = 1'b1;
        repeat (160) @(posedge clk);

        @(negedge clk);
        timbre_key_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        timbre_key_n = 1'b1;
        repeat (20) @(posedge clk);

        if (timbre_id != 4'd1) begin
            $display("FAIL: timbre switch expected 1, got %0d", timbre_id);
            $finish;
        end

        knob_raw_flat = {12'd2048, 12'd4095};
        repeat (200) @(posedge clk);
        if (!param_ready) begin
            $display("FAIL: ADC parameters not ready");
            $finish;
        end
        if ((knob_value_flat[6:0] < 7'd120) || (knob_value_flat[13:7] < 7'd55)) begin
            $display("FAIL: knob mapping incorrect knob0=%0d knob1=%0d", knob_value_flat[6:0], knob_value_flat[13:7]);
            $finish;
        end

        $display("PASS: tb_keyboard_extended notes=60,72 timbre=%0d knob0=%0d knob1=%0d", timbre_id, knob_value_flat[6:0], knob_value_flat[13:7]);
        $finish;
    end
endmodule