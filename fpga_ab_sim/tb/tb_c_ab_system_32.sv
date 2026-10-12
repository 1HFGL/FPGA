`timescale 1ns/1ps

module tb_c_ab_system_32;
    reg clk;
    reg rst_n;
    reg [12:0] key_n;
    reg [90:0] key_velocity_flat;
    reg pressure_valid;
    reg [11:0] pressure_raw;
    reg expr_valid;
    reg [4:0] expr_source_id;
    reg [6:0] expr_note;
    reg [15:0] expr_pitch_bend;
    reg [7:0] expr_aftertouch;
    reg [7:0] expr_vibrato_depth;
    reg [7:0] expr_vibrato_rate;
    reg test_enable;
    reg test_clear;
    reg timbre_key_n;
    reg [23:0] knob_raw_flat;
    reg knob_valid;
    reg [5:0] test_voices;
    wire sample_tick;
    wire signed [15:0] audio_sample;
    wire i2s_bclk;
    wire i2s_lrck;
    wire i2s_sdata;
    wire [31:0] voice_active;
    wire [31:0] voice_gate;
    wire [5:0] voice_count;
    wire [5:0] max_voice_count;
    wire [3:0] timbre_id;
    wire [13:0] knob_value_flat;
    wire param_ready;
    wire param_fault;
    wire [31:0] release_done;
    wire test_busy;
    wire test_done;

    integer timeout;
    integer sample_count;
    integer bclk_edges;
    reg audio_nonzero;
    reg release_seen;
    reg bclk_d;

    always #5 clk = ~clk;

    audio_system_top #(
        .KEY_COUNT        (13),
        .VOICES           (32),
        .CLK_HZ           (1000000),
        .SAMPLE_RATE      (10000),
        .I2S_BCLK_DIV     (2),
        .DEBOUNCE_CYCLES  (4),
        .TEST_HOLD_CYCLES (3000),
        .MAX_EVENTS       (64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .key_n(key_n),
        .key_velocity_flat(key_velocity_flat),
        .timbre_key_n(timbre_key_n),
        .pressure_valid(pressure_valid),
        .pressure_raw(pressure_raw),
        .knob_raw_flat(knob_raw_flat),
        .knob_valid(knob_valid),
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
        .sample_tick(sample_tick),
        .audio_sample(audio_sample),
        .i2s_bclk(i2s_bclk),
        .i2s_lrck(i2s_lrck),
        .i2s_sdata(i2s_sdata),
        .voice_active(voice_active),
        .voice_gate(voice_gate),
        .timbre_id(timbre_id),
        .knob_value_flat(knob_value_flat),
        .param_ready(param_ready),
        .param_fault(param_fault),
        .voice_count(voice_count),
        .max_voice_count(max_voice_count),
        .release_done(release_done),
        .test_busy(test_busy),
        .test_done(test_done)
    );

    always @(posedge clk) begin
        if (sample_tick) begin
            sample_count = sample_count + 1;
            if (audio_sample !== 16'sd0) begin
                audio_nonzero = 1'b1;
            end
            if (|release_done) begin
                release_seen = 1'b1;
            end
        end
        if (i2s_bclk !== bclk_d) begin
            bclk_edges = bclk_edges + 1;
            bclk_d = i2s_bclk;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        key_n = 13'h1FFF;
        key_velocity_flat = {13{7'd100}};
        pressure_valid = 1'b0;
        pressure_raw = 12'd0;
        expr_valid = 1'b0;
        expr_source_id = 5'd0;
        expr_note = 7'd0;
        expr_pitch_bend = 16'd0;
        expr_aftertouch = 8'd0;
        expr_vibrato_depth = 8'd0;
        expr_vibrato_rate = 8'd0;
        test_enable = 1'b0;
        test_clear = 1'b0;
        timbre_key_n = 1'b1;
        knob_raw_flat = {12'd4095, 12'd4095};
        knob_valid = 1'b1;
        test_voices = 6'd32;
        timeout = 0;
        sample_count = 0;
        bclk_edges = 0;
        audio_nonzero = 1'b0;
        release_seen = 1'b0;
        bclk_d = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        @(negedge clk);
        test_enable = 1'b1;

        timeout = 0;
        while ((voice_count < 6'd32) && (timeout < 400000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (voice_count < 6'd32) begin
            $display("FAIL: 4 voices not reached, count=%0d", voice_count);
            $finish;
        end

        timeout = 0;
        while ((sample_count < 120) && (timeout < 200000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!audio_nonzero) begin
            $display("FAIL: audio sample stayed zero");
            $finish;
        end
        if (bclk_edges == 0) begin
            $display("FAIL: I2S bclk did not toggle");
            $finish;
        end

        @(negedge clk);
        test_enable = 1'b0;

        timeout = 0;
        while ((voice_count != 6'd0) && (timeout < 1000000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (voice_count != 6'd0) begin
            $display("FAIL: voices did not release, count=%0d release_seen=%0b", voice_count, release_seen);
            $finish;
        end
        if (!release_seen) begin
            $display("FAIL: release_done was never asserted");
            $finish;
        end

        $display("PASS: tb_c_ab_system_32 voices_reached=%0d audio=1 i2s_edges=%0d", max_voice_count, bclk_edges);
        $finish;
    end
endmodule