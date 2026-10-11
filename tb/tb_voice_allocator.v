`timescale 1ns/1ps

module tb_voice_allocator;
    reg clk;
    reg rst_n;
    reg event_valid;
    wire event_ready;
    reg event_type;
    reg [5:0] event_source_id;
    reg [6:0] event_note;
    reg [6:0] event_velocity;
    reg [3:0] event_timbre;
    reg expr_valid;
    wire expr_ready;
    reg [5:0] expr_source_id;
    reg [6:0] expr_note;
    reg [15:0] expr_pitch_bend;
    reg [7:0] expr_aftertouch;
    reg [7:0] expr_vibrato_depth;
    reg [7:0] expr_vibrato_rate;
    reg [31:0] release_done;
    wire [31:0] voice_active;
    wire [31:0] voice_gate;
    wire [191:0] voice_source_id_flat;
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

    integer i;
    integer active_n;
    integer gate_n;
    integer note64_idx;
    integer note70_idx;
    integer note92_idx;
    reg found60;
    reg found64;
    reg found70;
    reg found92;

    always #5 clk = ~clk;

    voice_allocator #(
        .VOICES       (32),
        .IDX_WIDTH    (5),
        .COUNT_WIDTH  (6),
        .TIME_WIDTH   (32),
        .SOURCE_WIDTH (6),
        .BEND_WIDTH   (16),
        .EXPR_WIDTH   (8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_valid(event_valid),
        .event_ready(event_ready),
        .event_type(event_type),
        .event_source_id(event_source_id),
        .event_note(event_note),
        .event_velocity(event_velocity),
        .event_timbre(event_timbre),
        .expr_valid(expr_valid),
        .expr_ready(expr_ready),
        .expr_source_id(expr_source_id),
        .expr_note(expr_note),
        .expr_pitch_bend(expr_pitch_bend),
        .expr_aftertouch(expr_aftertouch),
        .expr_vibrato_depth(expr_vibrato_depth),
        .expr_vibrato_rate(expr_vibrato_rate),
        .release_done(release_done),
        .cancel_valid(1'b0), .cancel_ready(), .cancel_mask(6'd0), .cancel_value(6'd0),
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
        .steal_pulse(steal_pulse),
        .voice_trigger()
    );

    task send_note_on;
        input [6:0] note_value;
        input [5:0] source_value;
        begin
            wait (event_ready == 1'b1);
            @(negedge clk);
            event_valid = 1'b1;
            event_type = 1'b1;
            event_source_id = source_value;
            event_note = note_value;
            event_velocity = 7'd100;
            event_timbre = 4'd0;
            @(posedge clk);
            @(negedge clk);
            event_valid = 1'b0;
            wait (event_ready == 1'b1);
        end
    endtask

    task send_note_off;
        input [6:0] note_value;
        input [5:0] source_value;
        begin
            wait (event_ready == 1'b1);
            @(negedge clk);
            event_valid = 1'b1;
            event_type = 1'b0;
            event_source_id = source_value;
            event_note = note_value;
            event_velocity = 7'd0;
            event_timbre = 4'd0;
            @(posedge clk);
            @(negedge clk);
            event_valid = 1'b0;
            wait (event_ready == 1'b1);
        end
    endtask

    task send_expression;
        input [5:0] source_value;
        input [6:0] note_value;
        input [15:0] bend_value;
        input [7:0] touch_value;
        input [7:0] depth_value;
        input [7:0] rate_value;
        begin
            wait (expr_ready == 1'b1);
            @(negedge clk);
            expr_valid = 1'b1;
            expr_source_id = source_value;
            expr_note = note_value;
            expr_pitch_bend = bend_value;
            expr_aftertouch = touch_value;
            expr_vibrato_depth = depth_value;
            expr_vibrato_rate = rate_value;
            @(posedge clk);
            @(negedge clk);
            expr_valid = 1'b0;
            wait (expr_ready == 1'b1);
        end
    endtask

    task count_voices;
        begin
            active_n = 0;
            gate_n = 0;
            for (i = 0; i < 32; i = i + 1) begin
                if (voice_active[i]) active_n = active_n + 1;
                if (voice_gate[i]) gate_n = gate_n + 1;
            end
        end
    endtask

    task find_voice;
        input [6:0] note_value;
        output integer found_idx;
        output reg found_flag;
        begin
            found_idx = -1;
            found_flag = 1'b0;
            for (i = 0; i < 32; i = i + 1) begin
                if (voice_active[i] && (dut.note_mem[i] == note_value)) begin
                    found_idx = i;
                    found_flag = 1'b1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        event_valid = 1'b0;
        event_type = 1'b0;
        event_source_id = 6'd0;
        event_note = 7'd0;
        event_velocity = 7'd0;
        event_timbre = 4'd0;
        expr_valid = 1'b0;
        expr_source_id = 6'd0;
        expr_note = 7'd0;
        expr_pitch_bend = 16'd0;
        expr_aftertouch = 8'd0;
        expr_vibrato_depth = 8'd0;
        expr_vibrato_rate = 8'd0;
        release_done = 32'hFFFFFFFF;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        for (i = 0; i < 32; i = i + 1) begin
            send_note_on(7'd60 + i[6:0], i[5:0]);
        end

        repeat (2) @(posedge clk);
        @(negedge clk);
        count_voices();
        if ((voice_count != 6'd32) || (max_voice_count != 6'd32) ||
            (active_n != 32) || (gate_n != 32)) begin
            $display("FAIL: 32 voices expected, count=%0d max=%0d active=%0d gate=%0d", voice_count, max_voice_count, active_n, gate_n);
            $finish;
        end

        send_note_on(7'd92, 6'd32);
        find_voice(7'd60, note64_idx, found60);
        find_voice(7'd92, note92_idx, found92);
        if ((steal_count != 32'd1) || found60 || !found92) begin
            $display("FAIL: stealing expected, steal=%0d n60=%0b n92=%0b", steal_count, found60, found92);
            $finish;
        end

        release_done = 32'h00000000;
        send_note_off(7'd64, 6'd4);
        find_voice(7'd64, note64_idx, found64);
        if (!found64 || voice_gate[note64_idx] || !voice_active[note64_idx]) begin
            $display("FAIL: release wait failed, idx=%0d active=%0b gate=%0b", note64_idx, voice_active[note64_idx], voice_gate[note64_idx]);
            $finish;
        end

        release_done = 32'hFFFFFFFF;
        repeat (5) @(posedge clk);
        find_voice(7'd64, note64_idx, found64);
        if (found64) begin
            $display("FAIL: release_done did not clear note64");
            $finish;
        end

        find_voice(7'd70, note70_idx, found70);
        if (!found70) begin
            $display("FAIL: note70 not found before expression update");
            $finish;
        end
        if (dut.source_id_mem[note70_idx] != 6'd10) begin
            $display("FAIL: source_id 10 not stored for note70, got %0d", dut.source_id_mem[note70_idx]);
            $finish;
        end

        send_expression(6'd10, 7'd70, 16'h1234, 8'h55, 8'h22, 8'h33);
        if ((dut.pitch_bend_mem[note70_idx] != 16'h1234) ||
            (dut.aftertouch_mem[note70_idx] != 8'h55) ||
            (dut.vibrato_depth_mem[note70_idx] != 8'h22) ||
            (dut.vibrato_rate_mem[note70_idx] != 8'h33)) begin
            $display("FAIL: expression update failed, idx=%0d bend=%h touch=%h depth=%h rate=%h", note70_idx, dut.pitch_bend_mem[note70_idx], dut.aftertouch_mem[note70_idx], dut.vibrato_depth_mem[note70_idx], dut.vibrato_rate_mem[note70_idx]);
            $finish;
        end

        $display("PASS: tb_voice_allocator_32 voices=%0d max=%0d steal=%0d", voice_count, max_voice_count, steal_count);
        $finish;
    end
endmodule
