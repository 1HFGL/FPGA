`timescale 1ns/1ps

module tb_ads1115_knob_if;

    reg clk; reg rst_n;
    wire [13:0] knob_value_flat;
    wire param_ready; wire param_fault;
    wire scl; wire sda;
    pullup p_sda(sda); pullup p_scl(scl);
    integer t;

    always #5 clk = ~clk;

    ads1115_knob_if #(
        .CLK_HZ       (1000), .I2C_HZ       (100), .I2C_ADDR (7'h48),
        .PGA          (3'b001), .DR          (3'b100),
        .CH0_MUX      (4), .CH1_MUX      (5),
        .CONV_WAIT    (200), .READY_SAMPLES (4), .FAULT_TIMEOUT (5000)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sda(sda), .scl(scl),
        .knob_value_flat(knob_value_flat), .knob_sample_valid(),
        .param_ready(param_ready), .param_fault(param_fault)
    );

    ads1115_model #(.ADDR(7'h48), .CONV0(16'h4000), .CONV1(16'h2000), .CH0_MUX(4), .CH1_MUX(5)) model (
        .scl(scl), .sda(sda)
    );

    initial begin
        clk = 1'b0; rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        // Calibrated 0..3.3V range: 16384/26400 -> 79; 8192/26400 -> 39.
        for (t = 0; t < 300000; t = t + 1) begin
            @(posedge clk);
            if (param_ready && !param_fault &&
                knob_value_flat[6:0] == 7'd79 && knob_value_flat[13:7] == 7'd39) begin
                $display("PASS: tb_ads1115_knob_if knob0=%0d knob1=%0d ready=%0b fault=%0b",
                         knob_value_flat[6:0], knob_value_flat[13:7], param_ready, param_fault);
                $finish;
            end
        end
        $display("FAIL: tb_ads1115_knob_if knob0=%0d knob1=%0d ready=%0b", knob_value_flat[6:0], knob_value_flat[13:7], param_ready);
        $fatal(1, "ADS1115 knob chain failed");
    end

endmodule
