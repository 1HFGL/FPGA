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
module tb_input_sync_debounce_2ms;
    reg clk = 0;
    reg rst_n = 0;
    reg async_in = 1;
    wire level, press_pulse, release_pulse;
    integer press_count = 0;
    integer release_count = 0;
    time stable_start;
    time press_delay;
    time release_delay;

    always #10 clk = ~clk;
    input_sync_debounce dut (
        .clk(clk), .rst_n(rst_n), .async_in(async_in), .level(level),
        .press_pulse(press_pulse), .release_pulse(release_pulse)
    );
    always @(negedge clk) begin
        if (rst_n && press_pulse) press_count = press_count + 1;
        if (rst_n && release_pulse) release_count = release_count + 1;
    end

    initial begin
        repeat(5) @(negedge clk);
        rst_n = 1;
        repeat(10) @(negedge clk);
        // A 1ms low glitch must not turn into a note-on.
        async_in = 0;
        repeat(50000) @(negedge clk);
        async_in = 1;
        repeat(20) @(negedge clk);
        if (level !== 0 || press_count != 0 || release_count != 0)
            $fatal(1, "Short glitch accepted");

        // Separate unstable intervals must not accumulate toward the threshold.
        async_in = 0;
        repeat(80000) @(negedge clk);
        async_in = 1;
        repeat(500) @(negedge clk);
        async_in = 0;
        repeat(20000) @(negedge clk);
        async_in = 1;
        repeat(500) @(negedge clk);
        if (level !== 0 || press_count != 0) $fatal(1, "Press bounce accepted");
        async_in = 0;
        stable_start = $time;
        wait(press_pulse === 1);
        press_delay = $time - stable_start;
        if (press_delay < 2000000 || press_delay > 2000200)
            $fatal(1, "Unexpected default press latency: %0d ns", press_delay);
        repeat(125000) @(negedge clk);
        if (level !== 1 || press_count != 1) $fatal(1, "Repeated press during hold");

        // Release uses the same stable threshold and emits exactly one event.
        async_in = 1;
        repeat(80000) @(negedge clk);
        async_in = 0;
        repeat(500) @(negedge clk);
        if (level !== 1 || release_count != 0) $fatal(1, "Release bounce accepted");
        async_in = 1;
        stable_start = $time;
        wait(release_pulse === 1);
        release_delay = $time - stable_start;
        if (release_delay < 2000000 || release_delay > 2000200)
            $fatal(1, "Unexpected default release latency: %0d ns", release_delay);
        repeat(50000) @(negedge clk);
        if (level !== 0 || press_count != 1 || release_count != 1)
            $fatal(1, "Incorrect default debounce event count");
        $display("PASS: tb_input_sync_debounce_2ms press_ns=%0d release_ns=%0d on=%0d off=%0d",
                 press_delay, release_delay, press_count, release_count);
        $finish;
    end
    initial begin #20000000; $fatal(1, "2ms debounce watchdog"); end
endmodule
