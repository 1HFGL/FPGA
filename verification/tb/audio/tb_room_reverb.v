`timescale 1ns/1ps
module tb_room_reverb;
 reg clk=0,rst=0,valid=0;
 reg signed [15:0] sample=0;
 wire signed [15:0] y,y0,y128;
 wire ov,ov0,ov128,tail,t0,t128,busy,overrun;
 always #10 clk=~clk;
 room_reverb dut(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(y),.out_valid(ov),.tail_active(tail),.busy(busy),.overrun(overrun));
 room_reverb #(.WET_LEVEL(0)) dry(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(y0),.out_valid(ov0),.tail_active(t0),.busy(),.overrun());
 room_reverb #(.WET_LEVEL(128)) wet(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(y128),.out_valid(ov128),.tail_active(t128),.busy(),.overrun());
 integer fd,rc,reset_case,x,expected,expected_tail,w,ta0,ta128,n=0,j;
 initial begin
  fd=$fopen("build/regression/reverb/vectors.txt","r");
  if(fd==0)begin $display("FAIL missing room reference vectors");$finish;end
  repeat(4)@(negedge clk);rst=1;
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%d %d %d %d %d %d %d\n",reset_case,x,expected,expected_tail,w,ta0,ta128);
   if(rc!=7)begin $display("FAIL malformed vector");$finish;end
   if(reset_case)begin
    @(negedge clk);rst=0;valid=0;repeat(2)@(negedge clk);
    if(y!==0 || ov || tail || busy || overrun)begin $display("FAIL room reset state");$finish;end
    rst=1;
   end
   @(negedge clk);sample=x;valid=1;
   @(posedge clk);#1;
   if(ov || !busy)begin $display("FAIL room accept");$finish;end
   for(j=1;j<=8;j=j+1)begin
    @(negedge clk);valid=0;@(posedge clk);#1;
    if(j<8 && (ov || ov0 || ov128))begin $display("FAIL room early output");$finish;end
   end
   if(ov!==1 || ov0!==1 || ov128!==1 || busy || overrun ||
      $signed(y)!==expected || $signed(y0)!==x || $signed(y128)!==w ||
      tail!==expected_tail[0] || t0!==ta0[0] || t128!==ta128[0])begin
    $display("FAIL room vector %0d x=%0d y=%0d expected=%0d wet=%0d expwet=%0d tail=%b expected=%0d",n,x,y,expected,y128,w,tail,expected_tail);$finish;
   end
   n=n+1;
   // Uneven spacing also verifies valid strobes and no free-running delay drift.
   if(n%53==0)repeat(4)begin @(posedge clk);#1;if(ov)begin $display("FAIL duplicate valid");$finish;end end
  end
  $fclose(fd);
  // Reset while a sample is pending, then prove it never produces a stale valid.
  @(negedge clk);sample=12345;valid=1;@(negedge clk);valid=0;
  repeat(3)@(negedge clk);rst=0;repeat(2)@(negedge clk);rst=1;
  repeat(20)begin @(posedge clk);#1;if(ov || tail)begin $display("FAIL cancelled transaction");$finish;end end
  // Busy input is rejected with sticky diagnostics, never re-times the original sample.
  @(negedge clk);valid=1;sample=2000;@(negedge clk);sample=-2000;
  @(negedge clk);valid=0;wait(ov);#1;
  if(!overrun || y!=1500)begin $display("FAIL room overrun handling");$finish;end
  @(negedge clk);rst=0;repeat(2)@(negedge clk);
  if(overrun)begin $display("FAIL overrun reset");$finish;end
  $display("PASS tb_room_reverb: %0d independent vectors x 3 mixes, finite tails, dirty/pending resets, exact latency and overrun",n);$finish;
 end
 initial begin #200000000;$display("FAIL room unit timeout");$finish;end
endmodule
