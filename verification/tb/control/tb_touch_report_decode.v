`timescale 1ns/1ps
module tb_touch_report_decode;
 reg clk=0,rst=0,connected=1,valid=0,accept=0;
 reg [415:0] data=0;
 wire ready,frame,error;wire [5:0] active;wire [47:0] ids;wire [71:0] xs,ys;
 reg [415:0] inputs[0:4095];reg [198:0] expected[0:4095];
 reg [197:0] held;
 integer n,total=0,limit,good=0,bad=0;
 always #10 clk=~clk;
 touch_report_decode dut(.clk(clk),.rst_n(rst),.connected(connected),.report_valid(valid),
  .report_ready(ready),.report_data(data),.frame_valid(frame),.frame_ready(accept),
  .contact_active(active),.contact_id(ids),.contact_x(xs),.contact_y(ys),.stream_error(error));
 initial begin
  if(!$value$plusargs("COUNT=%d",total) || total<1 || total>4096)begin $display("FAIL replay count");$finish;end
  $readmemh("build/touch_driver_20261024/replay_input.mem",inputs,0,total-1);
  $readmemh("build/touch_driver_20261024/replay_expected.mem",expected,0,total-1);
  repeat(5)@(negedge clk);rst=1;
  for(n=0;n<total;n=n+1)begin
   while(!ready)@(negedge clk);
   data=inputs[n];valid=1;@(negedge clk);valid=0;limit=0;
   while(!frame && !error && limit<30)begin @(negedge clk);limit=limit+1;end
   if(limit==30 || error!==expected[n][198])begin $display("FAIL replay validity at %d",n);$finish;end
   if(error)begin bad=bad+1;@(negedge clk);end
   else begin
    held={ys,xs,ids,active};
    if(held!==expected[n][197:0])begin $display("FAIL replay fields at %d",n);$finish;end
    repeat(3)begin @(negedge clk);if(!frame || ready || {ys,xs,ids,active}!==held)begin $display("FAIL report backpressure");$finish;end end
    accept=1;@(negedge clk);accept=0;good=good+1;
   end
  end
  while(!ready)@(negedge clk);data=inputs[0];valid=1;@(negedge clk);valid=0;
  wait(frame);@(negedge clk);connected=0;@(negedge clk);
  if(frame || active!=0)begin $display("FAIL disconnect flush");$finish;end
  rst=0;@(negedge clk);if(frame || error || active!=0)begin $display("FAIL decoder reset");$finish;end
  $display("PASS tb_touch_report_decode: %0d valid snapshots, %0d rejected malformed reports, all six slots, mapping, held output, disconnect/reset",good,bad);$finish;
 end
endmodule
