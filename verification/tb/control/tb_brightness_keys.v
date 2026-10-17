`timescale 1ns/1ps
module tb_brightness_keys;
    reg clk=0,rst_n=0,req=0;
    reg [1:0] keys=3;
    wire [6:0] target,current;
    integer cycles=0,prior=127,changes=0,n;
    brightness_keys #(.DEBOUNCE_CYCLES(6),.REPEAT_CYCLES(100)) dut(
        .clk(clk),.rst_n(rst_n),.sample_request(req),.key_n(keys),.target(target),.current(current));
    always #10 clk=~clk;
    always @(negedge clk)begin cycles=cycles+1;req=(cycles%4==0);end
    always @(posedge clk)begin
        prior=current;#1;
        if(rst_n && ((current>prior+1) || (prior>current+1)))begin $display("FAIL slew jump");$finish;end
        if(rst_n && !req && current!=prior)begin $display("FAIL off-frame slew");$finish;end
    end
    task step;input integer count;begin repeat(count)@(negedge clk);end endtask
    initial begin
        step(4);rst_n=1;step(10);
        keys=2;step(2);keys=3;step(20);
        if(target!=127)begin $display("FAIL debounce");$finish;end
        keys=2;step(18);keys=3;step(72);
        if(target!=111 || current!=111)begin $display("FAIL one press");$finish;end
        keys=2;step(1100);keys=3;step(100);
        if(target!=0 || current!=0)begin $display("FAIL dark repeat/clamp");$finish;end
        keys=1;step(1100);keys=3;step(100);
        if(target!=127 || current!=127)begin $display("FAIL bright repeat/clamp");$finish;end
        keys=2;step(150);keys=0;step(150);
        if(target!=127 || current!=127)begin $display("FAIL both restore");$finish;end
        keys=3;step(15);rst_n=0;step(3);
        if(target!=127 || current!=127)begin $display("FAIL key reset");$finish;end
        $display("PASS tb_brightness_keys: debounce, step, hold, clamps, restore, frame slew, reset");$finish;
    end
    initial begin #1000000;$display("FAIL key timeout");$finish;end
endmodule
