`timescale 1ns/1ps

module tb_wave_lut;
    reg clk;
    reg rst;
    reg read_en;
    reg [9:0] addr;
    wire signed [15:0] sample;
    wire sample_valid;
    integer checks;
    integer k;
    integer expected;
    real sine_value;

    wave_lut dut (
        .clk(clk), .rst(rst), .read_en(read_en), .addr(addr),
        .sample(sample), .sample_valid(sample_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Drive at the falling edge; check after nonblocking assignments settle.
    task step;
        input test_rst;
        input test_en;
        input [9:0] test_addr;
        input signed [15:0] expected_sample;
        input expected_valid;
        begin
            @(negedge clk);
            rst = test_rst;
            read_en = test_en;
            addr = test_addr;
            @(posedge clk);
            #1;
            if ((sample !== expected_sample) ||
                (sample_valid !== expected_valid)) begin
                $display("FAIL: addr=%0d sample=%0d expected=%0d valid=%b expected_valid=%b",
                         addr, sample, expected_sample, sample_valid, expected_valid);
                $fatal(1, "wave_lut check failed");
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        rst = 1'b1;
        read_en = 1'b0;
        addr = 10'd0;
        checks = 0;

        // No VCD export: ModelSim records the selected Wave signals directly.
        step(1, 0, 10'd0,       16'sd0,     0);
        step(0, 1, 10'd0,       16'sd0,     1);
        step(0, 1, 10'd256,     16'sd32767, 1);
        step(0, 0, 10'd768,     16'sd32767, 0); // Idle holds the old sample.
        step(0, 1, 10'd512,     16'sd0,     1);
        step(0, 1, 10'd768,    -16'sd32767, 1);
        step(1, 1, 10'd256,     16'sd0,     0); // Reset wins over a read.
        step(0, 0, 10'd256,     16'sd0,     0);
        $display("Key-point, enable and reset checks passed.");

        // Independent mathematical reference: check every address in order.
        // Round to nearest integer, with half values away from zero.
        for (k = 0; k < 1024; k = k + 1) begin
            sine_value = 32767.0 * $sin(6.283185307179586 * k / 1024.0);
            if (sine_value >= 0.0)
                expected = $rtoi(sine_value + 0.5);
            else
                expected = $rtoi(sine_value - 0.5);
            step(0, 1, k[9:0], expected[15:0], 1);
        end

        step(0, 0, 10'd256, expected[15:0], 0);
        step(0, 1, 10'd0, 16'sd0, 1);
        step(1, 0, 10'd768, 16'sd0, 0);
        $display("PASS: all %0d checks passed; all 1024 ROM addresses verified.", checks);
        $stop;
    end

    initial begin
        #20000;
        $fatal(1, "Simulation timed out");
    end
endmodule
