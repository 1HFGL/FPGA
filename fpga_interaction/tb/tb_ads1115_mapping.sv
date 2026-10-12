`timescale 1ns/1ps
module tb_ads1115_mapping;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    tri sda;
    pullup(sda);
    wire scl;
    wire [13:0] values;
    wire ready, fault, valid;
    integer frames = 0;
    integer initial_frames;
    integer n;
    reg [6:0] previous;

    ads1115_knob_if #(
        .CLK_HZ(1000), .I2C_HZ(100), .CONV_WAIT(20),
        .READY_SAMPLES(2), .FAULT_TIMEOUT(5000), .RETRY_WAIT(20)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sda(sda), .scl(scl),
        .knob_value_flat(values), .knob_sample_valid(valid),
        .param_ready(ready), .param_fault(fault)
    );
    ads1115_model #(.CONV0(16'hffff), .CONV1(16'd13200)) model(.scl(scl), .sda(sda));

    always @(negedge clk) begin
        if (!rst_n) previous = 0;
        else begin
            if (((values[6:0] > previous) && (values[6:0] - previous > 8)) ||
                ((values[6:0] < previous) && (previous - values[6:0] > 8)))
                $fatal(1, "Slew overflow or overshoot");
            previous = values[6:0];
            if (valid) frames = frames + 1;
        end
    end

    initial begin
        repeat(5) @(negedge clk);
        rst_n = 1;
        repeat(65000) @(negedge clk);
        if (!ready || fault || values[6:0] !== 0 || values[13:7] !== 7'd64)
            $fatal(1, "Negative/midpoint mapping failed: %h", values);

        model.conversion0 = 16'd26400; // 3.3V at +/-4.096V PGA
        initial_frames = frames;
        n = 0;
        while (values[6:0] != 127 && n < 70000) begin
            @(negedge clk);
            n = n + 1;
        end
        if (values[6:0] != 127 || (frames - initial_frames) > 32)
            $fatal(1, "Fullscale mapping too slow: value=%0d frames=%0d", values[6:0], frames-initial_frames);
        $display("INFO: 0->127 settled in %0d acquisition pairs", frames-initial_frames);

        model.conversion0 = 16'h7fff; // Above calibrated maximum saturates.
        repeat(65000) @(negedge clk);
        if (values[6:0] !== 127) $fatal(1, "High clamp failed");
        model.conversion0 = 16'd0;
        repeat(65000) @(negedge clk);
        if (values[6:0] !== 0) $fatal(1, "Zero endpoint failed");
        $display("PASS: tb_ads1115_mapping negative/zero/midpoint/fullscale/saturation/slew");
        $finish;
    end
    initial begin #5000000; $fatal(1, "Mapping test watchdog"); end
endmodule
