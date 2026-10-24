`timescale 1ns/1ps
// Verify the actual GW5A DPB initialization, both concurrent read ports,
// independent enables, bank boundaries and every coefficient against the
// unchanged master ROM. No behavioral replacement of the vendor primitive.
module tb_dual16_rom;
 reg clk=0,ea=0,eb=0;
 always #10 clk=~clk;
 GSR GSR(.GSRI(1'b1));
 reg [13:0] aa=0,ab=0;
 reg [6:0] ma=0,mb=0;
 wire [75:0] qa,qb;
 reg [75:0] original[0:16383];
 reg [75:0] hold_a,hold_b;
 integer i,j,record_a,record_b,component_a,component_b;
 modal_coeff_rom_dual dut(.clk(clk),.en_a(ea),.en_b(eb),.address_a(aa),.address_b(ab),
  .metadata_a(ma),.metadata_b(mb),.data_a(qa),.data_b(qb));
 initial begin
  $readmemh("rtl/rom/piano_v3_modes.mem",original);
  repeat(4)@(negedge clk);
  for(i=0;i<12288;i=i+1)begin
   // Reverse and coprime-stride order force the two ports into different banks.
   j=(i*97+4095)%12288;
   aa=i;ab=j;record_a=i/48;record_b=j/48;component_a=i%48;component_b=j%48;
   ma=(record_a/128)*48+component_a;mb=(record_b/128)*48+component_b;
   ea=1;eb=1;@(posedge clk);#1;
   if(qa!==original[record_a*64+component_a] || qb!==original[record_b*64+component_b])begin
    $display("FAIL dual16 ROM i=%0d j=%0d got_a=%h ref_a=%h got_b=%h ref_b=%h",i,j,qa,original[record_a*64+component_a],qb,original[record_b*64+component_b]);$finish;
   end
   hold_a=qa;hold_b=qb;@(negedge clk);
   if((i%127)==0)begin
    ea=0;aa=0;ma=0;@(posedge clk);#1;
    if(qa!==hold_a || qb!==hold_b)begin $display("FAIL dual16 ROM enable A");$finish;end
    @(negedge clk);ea=1;aa=i;ma=(record_a/128)*48+component_a;eb=0;ab=0;mb=0;
    @(posedge clk);#1;
    if(qa!==hold_a || qb!==hold_b)begin $display("FAIL dual16 ROM enable B");$finish;end
    @(negedge clk);
   end
  end
  $display("PASS tb_dual16_rom: 24576 exact vendor-DPB reads; all notes/presets/modes, independent enables and bank crossings");$finish;
 end
 initial begin #1000000;$display("FAIL dual16 ROM timeout");$finish;end
endmodule
