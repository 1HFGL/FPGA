`timescale 1ns/1ps
module tb_touch_report_cdc;
 reg src_clk=0,dst_clk=0,rst=0,blocked=0;
 always #10.416 src_clk=~src_clk;
 always #10 dst_clk=~dst_clk;
 integer sent=0,received=0,cycle=0,epoch=0;
 wire sr,valid;wire [415:0] data;
 wire accept=!blocked && cycle%7<3;
 function [415:0] pattern;
  input integer n,e;integer i;
  begin for(i=0;i<13;i=i+1)pattern[i*32+:32]=(n*65537)^(i*1234567)^(e*7654321);end
 endfunction
 touch_report_cdc dut(.src_clk(src_clk),.src_rst_n(rst),.src_valid(sent<500),
  .src_data(pattern(sent,epoch)),.src_ready(sr),.dst_clk(dst_clk),.dst_rst_n(rst),
  .dst_ready(accept),.dst_valid(valid),.dst_data(data));
 always @(posedge src_clk or negedge rst)if(!rst)sent<=0;else if(sent<500 && sr)sent<=sent+1;
 always @(posedge dst_clk or negedge rst)begin
  if(!rst)begin received<=0;cycle<=0;end
  else begin
   cycle<=cycle+1;
   if(valid && accept)begin
    if(data!==pattern(received,epoch))begin $display("FAIL torn/stale/reordered CDC report %d epoch%d",received,epoch);$finish;end
    received<=received+1;
   end
  end
 end
 initial begin
  repeat(5)@(negedge dst_clk);rst=1;
  wait(received==500);@(negedge dst_clk);blocked=1;rst=0;epoch=1;
  repeat(3)@(negedge dst_clk);rst=1;wait(!sr);repeat(7)@(negedge dst_clk);
  rst=0;epoch=2;repeat(3)@(negedge dst_clk);rst=1;blocked=0;
  wait(received==500);repeat(10)@(negedge dst_clk);
  if(sent!=500 || valid)begin $display("FAIL CDC completion");$finish;end
  $display("PASS tb_touch_report_cdc: 1000 full-width 48/50MHz reports, stalls, reset with pending report, no torn/phantom data");$finish;
 end
 initial begin #2000000;$display("FAIL CDC timeout");$finish;end
endmodule
