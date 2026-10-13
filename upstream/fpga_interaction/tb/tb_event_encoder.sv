`timescale 1ns/1ps

module tb_event_encoder;
    reg clk;
    reg rst_n;
    reg [1:0] key_press;
    reg [1:0] key_release;
    reg [13:0] key_velocity_flat;
    reg [3:0] input_timbre;
    wire event_valid;
    wire event_type;
    wire [4:0] event_source_id;
    wire [6:0] event_note;
    wire [6:0] event_velocity;
    wire [3:0] event_timbre;
    wire event_ready;

    integer on_count;
    integer off_count;
    reg seen_note60_on;
    reg seen_note61_on;
    reg seen_note60_off;
    reg seen_note61_off;
    reg seen_velocity60;
    reg seen_velocity64;
    reg seen_source60;
    reg seen_source64;

    assign event_ready = 1'b1;

    always #5 clk = ~clk;

    event_encoder #(
        .KEY_COUNT    (2),
        .MAX_EVENTS   (64),
        .PTR_WIDTH    (6),
        .SOURCE_WIDTH (5)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .key_press          (key_press),
        .key_release        (key_release),
        .key_velocity_flat  (key_velocity_flat),
        .input_timbre       (input_timbre),
        .event_valid        (event_valid),
        .event_type         (event_type),
        .event_source_id    (event_source_id),
        .event_note         (event_note),
        .event_velocity     (event_velocity),
        .event_timbre       (event_timbre),
        .event_ready        (event_ready)
    );

    always @(negedge clk) begin
        if (event_valid) begin
            if (event_type) begin
                on_count = on_count + 1;
                if (event_note == 7'd60) begin
                    seen_note60_on = 1'b1;
                    if (event_velocity == 7'd90) seen_velocity60 = 1'b1;
                    if (event_source_id == 5'd0) seen_source60 = 1'b1;
                end
                if (event_note == 7'd61) begin
                    seen_note61_on = 1'b1;
                    if (event_velocity == 7'd110) seen_velocity64 = 1'b1;
                    if (event_source_id == 5'd1) seen_source64 = 1'b1;
                end
            end else begin
                off_count = off_count + 1;
                if (event_note == 7'd60) seen_note60_off = 1'b1;
                if (event_note == 7'd61) seen_note61_off = 1'b1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        key_press = 2'b00;
        key_release = 2'b00;
        key_velocity_flat = {7'd110, 7'd90};
        input_timbre = 4'd0;
        on_count = 0;
        off_count = 0;
        seen_note60_on = 1'b0;
        seen_note61_on = 1'b0;
        seen_note60_off = 1'b0;
        seen_note61_off = 1'b0;
        seen_velocity60 = 1'b0;
        seen_velocity64 = 1'b0;
        seen_source60 = 1'b0;
        seen_source64 = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        @(negedge clk);
        key_press = 2'b11;
        @(posedge clk);
        @(negedge clk);
        key_press = 2'b00;
        repeat (8) @(posedge clk);

        if ((on_count != 2) || !seen_note60_on || !seen_note61_on ||
            !seen_velocity60 || !seen_velocity64 || !seen_source60 || !seen_source64) begin
            $display("FAIL: note-on events on=%0d n60=%0b n64=%0b v60=%0b v64=%0b s60=%0b s64=%0b",
                     on_count, seen_note60_on, seen_note61_on, seen_velocity60, seen_velocity64, seen_source60, seen_source64);
            $finish;
        end

        @(negedge clk);
        key_release = 2'b11;
        @(posedge clk);
        @(negedge clk);
        key_release = 2'b00;
        repeat (8) @(posedge clk);

        if ((off_count != 2) || !seen_note60_off || !seen_note61_off) begin
            $display("FAIL: note-off events off=%0d n60=%0b n64=%0b", off_count, seen_note60_off, seen_note61_off);
            $finish;
        end

        $display("PASS: tb_event_encoder on=%0d off=%0d", on_count, off_count);
        $finish;
    end
endmodule