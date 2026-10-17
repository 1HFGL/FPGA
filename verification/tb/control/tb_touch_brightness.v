`timescale 1ns/1ps
module tb_touch_brightness;
 reg clk=0,rst=0,connected=0,valid=0,down=0;
 reg [11:0] x=0,y=0;
 wire [6:0] target;
 wire ready,drag;
 integer i,n=0,expected,old;
 always #10 clk=~clk;
 touch_brightness_control #(.TIMEOUT_CYCLES(20)) dut(.clk(clk),.rst_n(rst),
  .connected(connected),.report_valid(valid),.contact_down(down),.contact_x(x),.contact_y(y),
  .target(target),.available(ready),.dragging(drag));
 task report;input d;input integer px,py;
  begin @(negedge clk);valid=1;down=d;x=px;y=py;@(negedge clk);valid=0;n=n+1;end
 endtask
 task check;input integer value;input r,g;
  begin if(target!==value || ready!==r || drag!==g)begin
   $display("FAIL touch target=%0d expected=%0d ready=%b/%b drag=%b/%b event=%0d",target,value,ready,r,drag,g,n);$finish;end end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;check(127,0,0);
  report(1,352,50);check(127,0,0);connected=1;
  report(0,0,0);check(127,1,0);
  // Exhaustive horizontal mapping, including outside starts and clamped ends.
  for(i=0;i<1024;i=i+1)begin
   old=target;report(1,i,50);
   if(i>=336 && i<876)begin
    expected=(i-352)/4;if(expected<0)expected=0;if(expected>127)expected=127;
    check(expected,1,1);
   end else check(old,1,0);
   report(0,4095,4095);check(target,1,0);
  end
  // No capture on entering from elsewhere; reset requires a fresh down.
  report(1,100,50);report(1,352,50);check(127,1,0);report(0,0,0);
  report(1,352,40);check(0,1,1);report(1,608,73);check(64,1,1);
  report(1,900,30);check(64,1,1);report(1,0,55);check(0,1,1);
  report(1,1023,55);check(127,1,1);report(1,608,55);check(64,1,1);
  report(0,0,0);report(1,880,12);check(127,1,0);
  report(0,0,0);report(1,352,55);report(0,0,0);
  report(1,984,30);check(0,1,0);report(0,0,0);
  report(1,983,69);check(127,1,0);report(0,0,0);
  report(1,352,39);check(127,1,0);report(0,0,0);
  report(1,352,74);check(127,1,0);report(0,0,0);
  report(1,352,50);check(0,1,1);
  // Cable loss holds tone; fresh connection resumes without phantom events.
  connected=0;repeat(3)@(negedge clk);check(0,0,0);
  connected=1;report(1,608,50);check(64,1,1);
  repeat(22)@(negedge clk);check(64,0,0);
  report(1,860,50);check(64,1,0); // stale held contact cannot reclaim
  report(0,0,0);report(1,860,50);check(127,1,1);
  report(1,4095,50);check(127,0,0);
  report(1,352,50);check(127,1,0);report(0,0,0);
  report(1,352,50);check(0,1,1);
  for(i=0;i<30;i=i+1)begin repeat(5)@(negedge clk);report(1,608,50);check(64,1,1);end
  rst=0;repeat(2)@(negedge clk);check(127,0,0);
  $display("PASS tb_touch_brightness: %0d reports; all 1024 x positions, capture, reset, boundaries, malformed, disconnect and timeout",n);$finish;
 end
 initial begin #1000000;$display("FAIL touch unit timeout");$finish;end
endmodule
