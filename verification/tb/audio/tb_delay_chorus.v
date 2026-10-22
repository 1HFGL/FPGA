`timescale 1ns/1ps
module tb_delay_chorus;
 reg clk=0,rst=0,valid=0;
 reg signed [15:0] sample=0;
 wire signed [15:0] c,c0,c128,e,e0,e128;
 wire cv,cv0,cv128,ev,ev0,ev128,ct,et,cb,eb,co,eo;
 always #10 clk=~clk;
 chorus_effect chorus(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(c),.out_valid(cv),.tail_active(ct),.busy(cb),.overrun(co));
 chorus_effect #(.WET_LEVEL(0)) chorus_dry(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(c0),.out_valid(cv0),.tail_active(),.busy(),.overrun());
 chorus_effect #(.WET_LEVEL(128)) chorus_wet(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(c128),.out_valid(cv128),.tail_active(),.busy(),.overrun());
 echo_delay echo(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(e),.out_valid(ev),.tail_active(et),.busy(eb),.overrun(eo));
 echo_delay #(.WET_LEVEL(0)) echo_dry(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(e0),.out_valid(ev0),.tail_active(),.busy(),.overrun());
 echo_delay #(.WET_LEVEL(128)) echo_wet(.clk(clk),.rst_n(rst),.in_valid(valid),.sample_in(sample),
  .sample_out(e128),.out_valid(ev128),.tail_active(),.busy(),.overrun());
 integer fd,rc,reset_case,x,cy,cta,cw,ey,eta,ew,n=0,j,k;
 initial begin
  fd=$fopen("build/regression/effects/vectors.txt","r");
  if(fd==0)begin $display("FAIL missing effects vectors");$finish;end
  repeat(4)@(negedge clk);rst=1;
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%d %d %d %d %d %d %d %d\n",reset_case,x,cy,cta,cw,ey,eta,ew);
   if(rc!=8)begin $display("FAIL malformed effects vector");$finish;end
   if(reset_case)begin
    @(negedge clk);rst=0;valid=0;repeat(2)@(negedge clk);
    if(c!==0 || e!==0 || cv || ev || ct || et || cb || eb || co || eo)begin $display("FAIL effects reset");$finish;end
    rst=1;
   end
   @(negedge clk);sample=x;valid=1;@(posedge clk);#1;
   if(cv || ev || !cb || !eb)begin $display("FAIL effects accept");$finish;end
   for(j=1;j<=11;j=j+1)begin
    @(negedge clk);valid=0;@(posedge clk);#1;
    if(j==4)begin
     if(ev!==1 || ev0!==1 || ev128!==1 || eb || eo || $signed(e)!==ey || $signed(e0)!==x || $signed(e128)!==ew || et!==eta[0])
      begin $display("FAIL echo vector %0d x=%0d got=%0d expected=%0d wet=%0d expwet=%0d tail=%b exp=%0d",n,x,e,ey,e128,ew,et,eta);$finish;end
    end else if(ev || ev0 || ev128)begin $display("FAIL echo valid cycle");$finish;end
    if(j==11)begin
     if(cv!==1 || cv0!==1 || cv128!==1 || cb || co || $signed(c)!==cy || $signed(c0)!==x || $signed(c128)!==cw || ct!==cta[0])
      begin $display("FAIL chorus vector %0d x=%0d got=%0d expected=%0d wet=%0d expwet=%0d tail=%b exp=%0d",n,x,c,cy,c128,cw,ct,cta);$finish;end
    end else if(cv || cv0 || cv128)begin $display("FAIL chorus valid cycle");$finish;end
   end
   n=n+1;
   if(n%59==0)repeat(5)begin @(posedge clk);#1;if(cv || ev)begin $display("FAIL effects duplicate valid");$finish;end end
  end
  $fclose(fd);
  // Cancel at every pipeline phase, including after a delay-memory write.
  for(k=1;k<=11;k=k+1)begin
   @(negedge clk);sample=12345;valid=1;@(negedge clk);valid=0;
   repeat(k-1)@(negedge clk);rst=0;repeat(2)@(negedge clk);rst=1;
   repeat(15)begin @(posedge clk);#1;if(cv || ev || ct || et)begin $display("FAIL effects pending reset phase %0d",k);$finish;end end
  end
  @(negedge clk);valid=1;sample=2000;@(negedge clk);sample=-2000;@(negedge clk);valid=0;
  wait(ev);#1;if(!eo || e!=1750)begin $display("FAIL echo busy rejection");$finish;end
  wait(cv);#1;if(!co || c!=1625)begin $display("FAIL chorus busy rejection");$finish;end
  $display("PASS tb_delay_chorus: %0d vectors x 6 configurations, interpolation/LFO wraps, dry exactness, bounded tails, dirty/pending reset and overrun",n);$finish;
 end
 initial begin #400000000;$display("FAIL effects unit timeout");$finish;end
endmodule
