`timescale 1ns/1ps

module tb_pressure_if;
    reg clk;
    reg rst_n;
    reg sample_valid;
    reg [11:0] pressure_raw;
    wire [11:0] pressure_filtered;
    wire [6:0] velocity;
    wire pressure_active;

    integer i;

    always #5 clk = ~clk;

    pressure_if dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .sample_valid      (sample_valid),
        .pressure_raw      (pressure_raw),
        .pressure_filtered (pressure_filtered),
        .velocity          (velocity),
        .pressure_active   (pressure_active)
    );

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b0;
        sample_valid = 1'b0;
        pressure_raw = 12'd0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        for (i = 0; i < 200; i = i + 1) begin
            @(negedge clk);
            sample_valid = 1'b1;
            pressure_raw = 12'd4000;
            @(posedge clk);
        end

        @(negedge clk);
        sample_valid = 1'b0;
        repeat (2) @(posedge clk);

        if (pressure_active !== 1'b1) begin
            $display("FAIL: pressure_active should be high, filtered=%0d", pressure_filtered);
            $finish;
        end
        if (velocity == 0) begin
            $display("FAIL: velocity should be non-zero, filtered=%0d", pressure_filtered);
            $finish;
        end

        $display("PASS: tb_pressure_if filtered=%0d velocity=%0d", pressure_filtered, velocity);
        $finish;
    end
endmodule
