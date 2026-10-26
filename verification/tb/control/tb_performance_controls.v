`timescale 1ns/1ps
module tb_performance_controls;
    reg clk=0,rst=0,ready=1,tv=0,rv=0;
    always #10 clk=~clk;
    reg [2:0] keys=7;
    reg [3:0] tk=1,rk=2;
    wire tr,rr,valid,sustain;
    wire [3:0] kind;
    wire [7:0] value;
    integer count=0,i;
    reg [3:0] history[0:31];
    performance_controls #(.DEBOUNCE_CYCLES(3)) dut(.clk(clk),.rst_n(rst),.key_n(keys),
        .touch_valid(tv),.remote_valid(rv),.touch_ready(tr),.remote_ready(rr),
        .touch_kind(tk),.touch_value(8'd1),.remote_kind(rk),.remote_value(8'd2),
        .command_valid(valid),.command_ready(ready),.command_kind(kind),.command_value(value),.sustain(sustain));
    always @(posedge clk)if(rst && valid && ready)begin history[count]=kind;count=count+1;end
    task clocks;input integer n;begin repeat(n)begin @(posedge clk);#1;end end endtask
    task check;input ok;input [511:0] msg;begin if(ok!==1'b1)begin $display("FAIL %s",msg);$finish(1);end end endtask
    initial begin
        clocks(3);@(negedge clk);rst=1;
        // 短毛刺应被拒绝；长按只生成一次。
        @(negedge clk);keys=6;clocks(1);@(negedge clk);keys=7;clocks(10);
        check(count==0,"bounce accepted");
        @(negedge clk);keys=0;clocks(40);
        check(count==3 && history[0]==3 && history[1]==7 && history[2]==6,"K6/K7/K8 order");
        check(sustain,"sustain toggle missing");
        @(negedge clk);keys=7;clocks(10);
        // 输出等待期间到达其他来源不能替换已选择的命令。
        @(negedge clk);ready=0;tv=1;clocks(2);
        @(negedge clk);rv=1;keys=6;clocks(12);
        check(valid && kind==1 && value==1,"stalled payload replaced");
        @(negedge clk);ready=1;clocks(1);@(negedge clk);tv=0;
        clocks(1);@(negedge clk);rv=0;clocks(10);
        check(!sustain,"physical request starved");
        // 撤销触摸请求后不能因旧的锁定载荷执行幽灵操作。
        @(negedge clk);ready=0;tv=1;tk=3;clocks(2);
        @(negedge clk);tv=0;clocks(2);@(negedge clk);ready=1;clocks(2);
        check(!sustain,"cancelled touch toggled sustain");
        $display("PASS tb_performance_controls debounce, simultaneous keys, fair arbitration, stall/cancel");$finish;
    end
    initial begin #100000;$display("FAIL controls timeout");$finish(1);end
endmodule
