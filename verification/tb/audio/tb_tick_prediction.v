`timescale 1ns/1ps
module tick_case #(parameter integer F=50000000,R=48000,B=16,L=60)(input clk,rst_n,output reg [31:0] checks);
 wire a,b,c,x,y,z;
 sample_tick #(.AUDIO_CLK_HZ(F),.SAMPLE_RATE_HZ(R),.SLOT_BITS(B),.REQUEST_LEAD_HALF_EDGES(L)) dut(clk,rst_n,a,b,c);
 sample_tick_reference #(.AUDIO_CLK_HZ(F),.SAMPLE_RATE_HZ(R),.SLOT_BITS(B),.REQUEST_LEAD_HALF_EDGES(L)) ref_dut(clk,rst_n,x,y,z);
 reg [63:0] phase;integer edge_index;reg expected_ce,expected_frame,expected_prepare;
 initial begin checks=0;phase=0;edge_index=0;end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;edge_index<=0;end
  else if(phase+64'd4*B*R>=F)begin phase<=phase+64'd4*B*R-F;edge_index<=(edge_index==4*B-1)?0:edge_index+1;end
  else phase<=phase+64'd4*B*R;
 end
 always @(negedge clk or negedge rst_n or posedge rst_n)begin
  #0.1;
  expected_ce=rst_n && phase+64'd4*B*R>=F;
  expected_frame=expected_ce && edge_index==0;
  expected_prepare=expected_ce && edge_index==((L==0)?0:4*B-L);
  if({a,b,c}!=={x,y,z} || {a,b,c}!=={expected_ce,expected_frame,expected_prepare})begin
   $display("FAIL tick F=%0d R=%0d B=%0d L=%0d phase=%0d edge=%0d new=%b old=%b model=%b",F,R,B,L,phase,edge_index,{a,b,c},{x,y,z},{expected_ce,expected_frame,expected_prepare});$finish;
  end
  checks=checks+1;
 end
endmodule
module tb_tick_prediction;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 wire [31:0] n0,n1,n2,n3,n4,n5,n6,n7,n8,n9;
 tick_case c0(clk,rst_n,n0);
 tick_case #(25000000,48000,16,0)c1(clk,rst_n,n1);
 tick_case #(64,1,16,1)c2(clk,rst_n,n2);
 tick_case #(5,1,1,3)c3(clk,rst_n,n3);
 tick_case #(8,1,1,0)c4(clk,rst_n,n4);
 tick_case #(7,1,1,1)c5(clk,rst_n,n5);
 tick_case #(100003,1,1,0)c6(clk,rst_n,n6);
 tick_case #(17,2,2,7)c7(clk,rst_n,n7);
 tick_case #(49000000,48000,16,60)c8(clk,rst_n,n8);
 tick_case #(3072001,48000,16,60)c9(clk,rst_n,n9);
 integer i;
 initial begin
  #2;rst_n=1;#1;rst_n=0;#10;rst_n=1;
  repeat(300010)@(posedge clk);
  for(i=0;i<100;i=i+1)begin #3;rst_n=0;#(7+i%13);rst_n=1;repeat(31+i%97)@(posedge clk);end
  #2;$display("PASS tb_tick_prediction: ten parameter sets, exact baseline+independent accumulator, checks=%0d",n0+n1+n2+n3+n4+n5+n6+n7+n8+n9);$finish;
 end
 initial begin #5000000;$display("FAIL tick timeout");$finish;end
endmodule
