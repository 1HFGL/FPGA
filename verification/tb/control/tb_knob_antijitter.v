`timescale 1ns/1ps
module tb_knob_antijitter;
    reg clk=0,rst_n=0,valid=0;
    reg [29:0] raw=0;
    wire [13:0] value;
    wire ready,fault,pvalid;
    integer n;
    always #10 clk=~clk;
    adc_knob_if #(.ADC_WIDTH(15),.KNOB_COUNT(2),.READY_SAMPLES(1),
        .FAULT_TIMEOUT(32),.FILTER_SHIFT(0),.SLEW_STEP(127)
`ifndef BASELINE
        ,.HYSTERESIS_COUNTS(384),.CENTER_CHANNEL(1)
`endif
    ) dut(.clk(clk),.rst_n(rst_n),.sample_valid(valid),.raw_flat(raw),
        .value_flat(value),.param_valid(pvalid),.ready(ready),.fault(fault));
    task sample;
        input [14:0] volume,bend;
        begin
            @(negedge clk);raw={bend,volume};valid=1;
            @(negedge clk);valid=0;
            if(!pvalid || !ready || fault)begin $display("FAIL sample handshake");$finish;end
            @(negedge clk);
            if(pvalid)begin $display("FAIL sample pulse width");$finish;end
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        sample(16512,16384);
        if(value!=={7'd64,7'd64})begin $display("FAIL initial center");$finish;end
        // Raw noise crosses two quantizer boundaries; no rotary motion occurred.
        for(n=0;n<200;n=n+1)begin
            sample(n[0]?16712:16312,n[0]?16584:16184);
            if(value!=={7'd64,7'd64})begin $display("FAIL stationary jitter n=%d value=%h",n,value);$finish;end
        end
        sample(24576,25088);
        if(value!=={7'd98,7'd96})begin $display("FAIL real step delayed");$finish;end
        sample(24576,16160);
        if(value[13:7]!==64)begin $display("FAIL bend did not return to center");$finish;end
        sample(0,0);
        sample(200,200);
        if(value!==0)begin $display("FAIL bottom endpoint jitter");$finish;end
        sample(32767,32767);
        sample(32567,32567);
        if(value!==14'h3fff)begin $display("FAIL top endpoint jitter");$finish;end
        // Slow movement accumulates relative to the held reference, never sticks forever.
        for(n=0;n<=32767;n=n+127)sample(n,n);
        sample(32767,32767);
        if(value!==14'h3fff)begin $display("FAIL slow sweep endpoint");$finish;end
        repeat(40)@(negedge clk);
        if(!fault || ready)begin $display("FAIL timeout");$finish;end
        sample(10000,13200);
        if(value!=={7'd51,7'd39})begin $display("FAIL recovery seed");$finish;end
        rst_n=0;#1;
        if(value!==0 || pvalid || ready || fault)begin $display("FAIL reset");$finish;end
        $display("PASS tb_knob_antijitter: boundary noise, center, immediate steps, endpoints, slow sweep, timeout/recovery/reset");$finish;
    end
endmodule
