`timescale 1ns/1ps

module tb_ads1115_if;

    reg clk;
    reg rst_n;
    wire [31:0] raw_flat;
    wire sample_valid;
    wire fault;

    wire scl;
    wire sda;
    pullup p_sda(sda);
    pullup p_scl(scl);

    reg sample_seen;
    reg [31:0] captured;
    integer t;

    always #5 clk = ~clk;

    ads1115_if #(
        .CLK_HZ       (1000),
        .I2C_HZ       (100),
        .I2C_ADDR     (7'h48),
        .PGA          (3'b001),
        .DR           (3'b100),
        .CH0_MUX      (4),
        .CH1_MUX      (5),
        .CONV_WAIT    (300),
        .STARTUP_WAIT (50)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .raw_flat     (raw_flat),
        .sample_valid (sample_valid),
        .fault        (fault),
        .sda          (sda),
        .scl          (scl)
    );

    ads1115_model #(
        .ADDR   (7'h48),
        .CONV0  (16'h4000),
        .CONV1  (16'h2000),
        .CH0_MUX(4),
        .CH1_MUX(5)
    ) model (
        .scl (scl),
        .sda (sda)
    );

    always @(posedge clk) begin
        if (sample_valid) begin
            sample_seen <= 1'b1;
            captured <= raw_flat;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_seen = 1'b0;
        captured = 32'd0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (t = 0; t < 200000; t = t + 1) begin
            @(posedge clk);
            if (sample_seen) begin
                if (!fault && captured[15:0] == 16'h4000 && captured[31:16] == 16'h2000) begin
                    $display("PASS: tb_ads1115_if raw={chn1=%0h,chn0=%0h}", captured[31:16], captured[15:0]);
                    $finish;
                end
            end
        end

        $display("FAIL: tb_ads1115_if no sample captured (seen=%0b raw=%0h)", sample_seen, captured);
        $fatal(1, "ADS1115 acquisition failed");
    end

endmodule
