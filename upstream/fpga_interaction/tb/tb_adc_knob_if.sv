`timescale 1ns/1ps

module tb_adc_knob_if;
    reg clk;
    reg rst_n;
    reg sample_valid;
    reg [23:0] raw_flat;
    wire [13:0] value_flat;
    wire param_valid;
    wire ready;
    wire fault;
    integer i;

    always #5 clk = ~clk;

    adc_knob_if #(
        .ADC_WIDTH     (12),
        .KNOB_COUNT    (2),
        .READY_SAMPLES (4),
        .FAULT_TIMEOUT (20),
        .VALUE_WIDTH   (7)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_valid(sample_valid),
        .raw_flat    (raw_flat),
        .value_flat  (value_flat),
        .param_valid (param_valid),
        .ready       (ready),
        .fault       (fault)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid = 1'b0;
        raw_flat = 24'd0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (25) @(negedge clk);
        if (!fault || ready || param_valid || value_flat != 0)
            $fatal(1, "ADC absent from startup was not detected");

        raw_flat = {12'd2048, 12'd4095};
        // 前 4 个采样后，输出不应瞬间跳到终值（证明抗拉链平滑生效）
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            sample_valid = 1'b1;
            @(posedge clk);
        end
        @(negedge clk);
        if (!ready || fault)
            $fatal(1, "ready must assert on exactly READY_SAMPLES valid samples");
        if (value_flat[6:0] > 7'd8) begin
            $display("FAIL: knob0 changed too fast (slew not applied): %0d", value_flat[6:0]);
            $finish;
        end
        for (i = 4; i < 200; i = i + 1) begin
            @(negedge clk);
            sample_valid = 1'b1;
            @(posedge clk);
        end
        @(negedge clk);
        sample_valid = 1'b0;
        repeat (3) @(posedge clk);

        if (!ready) begin
            $display("FAIL: ADC knob ready did not assert");
            $finish;
        end
        if (value_flat[6:0] < 7'd120) begin
            $display("FAIL: knob0 value too low: %0d", value_flat[6:0]);
            $finish;
        end
        if (value_flat[13:7] < 7'd55) begin
            $display("FAIL: knob1 value too low: %0d", value_flat[13:7]);
            $finish;
        end

        repeat (35) @(posedge clk);
        if (!fault) begin
            $display("FAIL: ADC fault did not assert after timeout");
            $finish;
        end
        if (ready) $fatal(1, "ready remained set after sample timeout");

        @(negedge clk);
        sample_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        sample_valid = 1'b0;
        repeat (2) @(posedge clk);
        if (fault) begin
            $display("FAIL: ADC fault did not clear");
            $finish;
        end
        if (ready) $fatal(1, "ready recovered without the required warm-up samples");

        $display("PASS: tb_adc_knob_if knob0=%0d knob1=%0d", value_flat[6:0], value_flat[13:7]);
        $finish;
    end
endmodule
