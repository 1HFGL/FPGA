`timescale 1ns/1ps
// 固定Git原版16实例作参考；验证逐槽期限、整组结果、输入快照和复位。
module env_bank_case #(parameter [31:0] P=4096,G=2048)(output reg done=0);
 reg clk=0,rst_n=0,start=0;
 always #5 clk=~clk;
 reg [15:0] gate=0,note_on=0,instrument=0;
 reg [15:0] ref_gate=0,ref_start=0,ref_instrument=0;
 reg ref_tick=0;
 wire [271:0] levels,reference;
 wire [15:0] active,ref_active;
 wire busy;
 integer phase=-1,i,frame,j,checks=0,resets=0;
 reg [31:0] rng=32'h37ef419a;
 instrument_env_bank16 #(.P_RELEASE(P),.G_RELEASE(G)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.gate(gate),.note_on(note_on),.instrument(instrument),
  .env_level_flat(levels),.active(active),.busy(busy));
 genvar v;
 generate for(v=0;v<16;v=v+1)begin:g_ref
  instrument_env_reference #(.G_ATTACK(16),.G_DECAY(1),.G_SUSTAIN(65536),.G_RELEASE(G),
   .S_ATTACK(64),.S_DECAY(1),.S_SUSTAIN(65536),.S_RELEASE(P)) old(
   .clk(clk),.rst(!rst_n),.sample_tick(ref_tick),.gate(ref_gate[v]),.note_on(ref_start[v]),
   .instrument(ref_instrument[v]),.env_level(reference[v*17+:17]),.active(ref_active[v]),.state());
 end endgenerate
 always @(posedge clk)begin
  if(!rst_n)begin ref_tick<=0;phase=-1;end
  else begin
   ref_tick<=start && !busy;
   if(start && !busy)begin
    ref_gate<=gate;ref_start<=note_on;ref_instrument<=instrument;phase=0;
   end else if(phase>=0)phase=phase+1;
  end
  #1;
  if(!rst_n)begin
   if(levels!==0 || active!==0 || busy!==0)begin $display("FAIL bank reset");$stop;end
   resets=resets+1;
  end else if(phase>=1)begin
   for(i=0;i<16;i=i+1)if(i<phase)begin
    if(levels[i*17+:17]!==reference[i*17+:17] || active[i]!==ref_active[i])begin
     $display("FAIL bank equivalence P=%0d G=%0d frame=%0d phase=%0d slot=%0d got=%0d ref=%0d",P,G,frame,phase,i,levels[i*17+:17],reference[i*17+:17]);$stop;
    end
    checks=checks+1;
   end
   if(phase>=16 && busy)begin $display("FAIL bank deadline");$stop;end
  end
 end
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(frame=0;frame<6200;frame=frame+1)begin
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   if(frame<700)begin gate=rng[15:0];note_on=rng[31:16];instrument=rng[23:8];end
   else if(frame<1100)begin gate=16'hffff;note_on=(frame==700)?16'hffff:0;instrument=16'haaaa;end
   else begin gate=0;note_on=0;instrument=16'haaaa;end
   start=1;@(negedge clk);start=0;
   // R0之后立刻改变外部输入，不得影响这批后续15槽。
   gate=~gate;note_on=16'hffff;instrument=~instrument;
   for(j=0;j<22;j=j+1)begin
    if(frame==352 && j==6)rst_n=0;
    if(frame==352 && j==9)rst_n=1;
    @(negedge clk);
   end
  end
  if(checks<1000000 || resets<6)begin $display("FAIL bank coverage");$stop;end
  if(P<=4096 && (active!==0 || levels!==0))begin $display("FAIL bank release completion");$stop;end
  $display("PASS bank case P=%0d G=%0d frames=6200 checks=%0d resets=%0d",P,G,checks,resets);done=1;
 end
endmodule
module tb_env_bank_equivalence;
 wire a,b,c;
 env_bank_case #(4096,2048) actual(a);
 env_bank_case #(13,7) fractional(b);
 env_bank_case #(65537,1) wide(c);
 initial begin wait(a && b && c);$display("PASS tb_env_bank_equivalence");$finish;end
 initial begin #2000000;$display("FAIL bank timeout");$stop;end
endmodule
