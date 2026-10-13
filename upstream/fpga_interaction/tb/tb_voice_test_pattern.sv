`timescale 1ns/1ps

module tb_voice_test_pattern;
    reg clk;
    reg rst_n;
    reg test_enable;
    reg test_clear;
    reg [5:0] test_voices;
    wire test_event_valid;
    reg test_event_ready;
    wire test_event_type;
    wire [4:0] test_source_id;
    wire [6:0] test_note;
    wire [6:0] test_velocity;
    wire [3:0] test_timbre;
    wire test_busy;
    wire test_done;

    integer on_count;
    integer off_count;
    integer i;

    always #5 clk = ~clk;

    voice_test_pattern #(
        .SOURCE_WIDTH (5),
        .NOTE_BASE    (36),
        .HOLD_CYCLES  (20)
    ) dut (
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

    always @(negedge clk) begin
        if (test_event_valid && test_event_ready) begin
            if (test_event_type) begin
                on_count = on_count + 1;
            end else begin
                off_count = off_count + 1;
                if (off_count == 4) begin
                    test_enable = 1'b0;
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        test_enable = 1'b0;
        test_clear = 1'b0;
        test_voices = 6'd4;
        test_event_ready = 1'b1;
        on_count = 0;
        off_count = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        @(negedge clk);
        test_enable = 1'b1;

        repeat (80) @(posedge clk);

        if (on_count != 4) begin
            $display("FAIL: expected 4 note_on, got %0d", on_count);
            $finish;
        end
        if (off_count < 4) begin
            $display("FAIL: expected at least 4 note_off, got %0d", off_count);
            $finish;
        end

        test_enable = 1'b0;
        repeat (5) @(posedge clk);
        $display("PASS: tb_voice_test_pattern on=%0d off=%0d", on_count, off_count);
        $finish;
    end
endmodule