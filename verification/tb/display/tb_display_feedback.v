`timescale 1ns/1ps
module tb_display_feedback;
    reg clk=0,rst=0,commit=0,mode=0;
    reg [12:0] held=0;
    reg [15:0] raw=0;
    wire [38:0] activity;
    wire [15:0] level,peak;
    integer n;reg [15:0] prev_level,prev_peak;
    always #10 clk=~clk;
    display_feedback dut(.pixel_clk(clk),.rst_n(rst),.frame_commit(commit),.held(held),
        .instrument_guitar(mode),.raw_peak(raw),.activity(activity),.meter_level(level),.meter_peak(peak));
    task frame;
        begin @(negedge clk);commit=1;@(negedge clk);commit=0;end
    endtask
    initial begin
        #3;rst=1;held=13'h91;raw=32768;frame;
        if(activity[2:0]!=7 || level!=32768 || peak!=32768)begin $display("FAIL immediate feedback");$finish;end
        repeat(20)@(negedge clk);
        if(activity[2:0]!=7)begin $display("FAIL feedback changed outside frame");$finish;end
        held=0;raw=0;frame;
        if(activity[2:0]!=7 || level!=31744 || peak!=32768)begin $display("FAIL release/hold");$finish;end
        for(n=0;n<90;n=n+1)begin
            prev_level=level;prev_peak=peak;frame;
            if(level>prev_level || peak>prev_peak)begin $display("FAIL meter wrapped");$finish;end
        end
        if(activity!=0 || level!=0 || peak!=0)begin $display("FAIL feedback did not settle");$finish;end
        mode=1;held=1;frame;if(activity[2:0]!=7)begin $display("FAIL mode feedback");$finish;end
        #3;rst=0;#1;if(level!=0 || peak!=0 || activity!=0)begin $display("FAIL feedback reset");$finish;end
        $display("PASS tb_display_feedback: frame-only updates, release fade, raw meter peak hold/decay, mode and reset");$finish;
    end
endmodule
