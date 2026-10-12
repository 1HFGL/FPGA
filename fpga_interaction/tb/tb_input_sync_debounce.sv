`timescale 1ns/1ps

module tb_input_sync_debounce;
    reg clk;
    reg rst_n;
    reg async_in;
    wire level;
    wire press_pulse;
    wire release_pulse;

    integer press_count;
    integer release_count;

    always #5 clk = ~clk;

    input_sync_debounce #(
        .ACTIVE_LOW      (1),
        .DEBOUNCE_CYCLES (4)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .async_in      (async_in),
        .level         (level),
        .press_pulse   (press_pulse),
        .release_pulse (release_pulse)
    );

    always @(negedge clk) begin
        if (press_pulse) begin
            press_count = press_count + 1;
        end
        if (release_pulse) begin
            release_count = release_count + 1;
        end
    end

    initial begin
        clk         = 1'b0;
        rst_n       = 1'b0;
        async_in    = 1'b1;
        press_count = 0;
        release_count = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        if ((press_count != 0) || (release_count != 0) || (level !== 1'b0)) begin
            $display("FAIL: false edge after reset press=%0d release=%0d level=%0b", press_count, release_count, level);
            $finish;
        end

        @(negedge clk);
        async_in = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        async_in = 1'b1;
        @(posedge clk);
        @(negedge clk);
        async_in = 1'b0;
        @(posedge clk);
        @(negedge clk);
        async_in = 1'b1;
        @(posedge clk);
        @(negedge clk);
        async_in = 1'b0;
        repeat (12) @(posedge clk);

        if (level !== 1'b1) begin
            $display("FAIL: debounced level should be pressed");
            $finish;
        end
        if (press_count != 1) begin
            $display("FAIL: expected one press pulse, got %0d", press_count);
            $finish;
        end

        @(negedge clk);
        async_in = 1'b1;
        repeat (12) @(posedge clk);

        if (level !== 1'b0) begin
            $display("FAIL: debounced level should be released");
            $finish;
        end
        if (release_count != 1) begin
            $display("FAIL: expected one release pulse, got %0d", release_count);
            $finish;
        end

        $display("PASS: tb_input_sync_debounce press=%0d release=%0d", press_count, release_count);
        $finish;
    end
endmodule

// Use the actual 50 MHz clock and default parameter, not accelerated debounce.
