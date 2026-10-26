`timescale 1ns/1ps
module tb_usb_dual_clock;
 reg sys_clk=0,clock_on=1,pll_rst_n=0,rst_n=0;
 always #10 if(clock_on)sys_clk=~sys_clk;
 wire core_clk,pin_clk,locked;
 GSR GSR(.GSRI(1'b1));
 usb_clock_60k clocks(.sys_clk(sys_clk),.rst_n(pll_rst_n),.usb_clk(core_clk),.usb_pin_clk(pin_clk),.locked(locked));
 tri dp,dm;
 reg reset_bus=0,disable_tx=1,data_p=0,data_n=0;
 integer epoch,k,phase_checks=0,pin_checks=0;
 reg expected_drive,expected_dp,expected_dm;
 realtime previous_rise;
 touch_usb_port #(.SEPARATE_PIN_CLOCK(1)) dut(.clk(core_clk),.pin_clk(pin_clk),.rst_n(rst_n),
  .usb_dp(dp),.usb_dm(dm),.report_ready(1'b0));
 always @(posedge core_clk) if(locked && rst_n)begin
  #0.001;
  if(pin_clk!==1'b1)begin $display("FAIL dual PLL rising phase");$finish;end
  if(previous_rise!=0 && ($realtime-previous_rise<20.7 || $realtime-previous_rise>20.9))begin
   $display("FAIL dual PLL period %f",$realtime-previous_rise);$finish;end
  previous_rise=$realtime;phase_checks=phase_checks+1;
 end
 always @(negedge core_clk) if(locked && rst_n)begin
  #0.001;if(pin_clk!==1'b0)begin $display("FAIL dual PLL falling phase");$finish;end
  phase_checks=phase_checks+1;
 end
 initial begin
  force dut.bus_reset=reset_bus;force dut.oe=disable_tx;
  force dut.dp_out=data_p;force dut.dm_out=data_n;
  previous_rise=0;
  for(epoch=0;epoch<8;epoch=epoch+1)begin
   rst_n=0;pll_rst_n=0;#(101+epoch*7);clock_on=1;pll_rst_n=1;
   wait(locked);repeat(8)@(negedge core_clk);previous_rise=0;rst_n=1;
   for(k=0;k<1024;k=k+1)begin
    @(negedge core_clk);#1;
    reset_bus=(k%13==0);disable_tx=(k%7==0);data_p=k%2;data_n=(k/2)%2;
    expected_drive=reset_bus || !disable_tx;expected_dp=reset_bus?1'b0:data_p;expected_dm=reset_bus?1'b0:data_n;
    @(posedge core_clk);#1;
    if(dp!==(expected_drive?expected_dp:1'bz) || dm!==(expected_drive?expected_dm:1'bz))begin
     $display("FAIL dual pin same-cycle value epoch=%0d k=%0d",epoch,k);$finish;end
    pin_checks=pin_checks+1;
   end
   @(negedge core_clk);reset_bus=0;disable_tx=0;data_p=1;data_n=0;
   @(posedge core_clk);#1;
   #(epoch+1);rst_n=0;#0.001;
   if(dp!==1'bz || dm!==1'bz)begin $display("FAIL dual pin asynchronous release");$finish;end
   clock_on=0;pll_rst_n=0;#200;rst_n=1;#500;
   if(dp!==1'bz || dm!==1'bz)begin $display("FAIL dual stopped-clock output");$finish;end
   rst_n=0;disable_tx=1;
  end
  if(phase_checks<16000 || pin_checks!=8192)begin $display("FAIL dual clock coverage");$finish;end
  $display("PASS tb_usb_dual_clock: %0d phase/period checks, %0d pin values, 8 reset/clock-stop epochs",phase_checks,pin_checks);$finish;
 end
 initial begin #2000000;$display("FAIL dual clock timeout");$finish;end
endmodule
