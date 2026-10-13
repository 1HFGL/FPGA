`timescale 1ns/1ps
module tb_ads1115_faults;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    tri sda;
    pullup(sda);
    wire scl;
    wire [13:0] values;
    wire ready, fault, valid;
    integer samples = 0;
    integer before_samples;
    integer k;
    reg [13:0] held;

    ads1115_knob_if #(
        .CLK_HZ(1000), .I2C_HZ(100), .CONV_WAIT(20),
        .READY_SAMPLES(2), .FAULT_TIMEOUT(5000), .RETRY_WAIT(20)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sda(sda), .scl(scl),
        .knob_value_flat(values), .knob_sample_valid(valid),
        .param_ready(ready), .param_fault(fault)
    );
    ads1115_model model(.scl(scl), .sda(sda));

    always @(negedge clk) if (rst_n && valid) samples = samples + 1;

    task reset_driver;
        begin
            rst_n = 0;
            repeat(5) @(negedge clk);
            samples = 0;
            rst_n = 1;
        end
    endtask

    task expect_fault;
        begin
            repeat(14000) @(negedge clk);
            if (fault !== 1 || ready !== 0 || samples != 0 || values !== 0)
                $fatal(1, "Bad fault state fault=%b ready=%b samples=%0d values=%h",
                       fault, ready, samples, values);
        end
    endtask

    initial begin
        // No ADC from boot must never publish a parameter or become ready.
        model.connected = 0;
        reset_driver();
        expect_fault();
        model.connected = 1;
        repeat(24000) @(negedge clk);
        if (!ready || fault || samples < 2) $fatal(1, "Reconnect failed");

        // Disconnect after valid operation: hold the last parameter values.
        model.connected = 0;
        repeat(6000) @(negedge clk);
        held = values;
        before_samples = samples;
        repeat(6000) @(negedge clk);
        if (!fault || ready || values !== held || samples != before_samples)
            $fatal(1, "Disconnected device updated parameters");
        model.connected = 1;
        repeat(24000) @(negedge clk);
        if (!ready || fault || samples <= before_samples) $fatal(1, "Recovery failed");

        // Configuration transaction: address, pointer, MSB and LSB NACK.
        for (k = 0; k < 4; k = k + 1) begin
            model.nack_byte = k;
            reset_driver();
            expect_fault();
        end
        model.nack_byte = -1;
        model.nack_read_address = 1;
        reset_driver();
        expect_fault();
        model.nack_read_address = 0;
        model.nack_conversion_pointer = 1;
        reset_driver();
        expect_fault();
        model.nack_conversion_pointer = 0;

        // An ADC at 0x48 must not acknowledge a master configured for 0x49.
        force dut.u_ads.addr_w = 8'h92;
        reset_driver();
        expect_fault();
        release dut.u_ads.addr_w;
        repeat(24000) @(negedge clk);
        if (!ready || fault) $fatal(1, "Recovery after address mismatch failed");
        $display("PASS: tb_ads1115_faults missing/disconnect/reconnect/all_write_ACK/address");
        $finish;
    end

    initial begin #5000000; $fatal(1, "Fault test watchdog"); end
endmodule
