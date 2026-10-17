`timescale 1ns/1ps
// Real formal debounce defaults and HDMI clocks. ADC is injected identically on both tops.
module tb_hdmi_octaves;
 reg clk=0,rst=0;
 reg [1:0] bk=3;
 reg [12:0] keys=13'h1fff;
 tri1 sda1,sda2;
 wire [2:0] a,b;
 wire pa1,pa2,scl1,scl2;
 GSR GSR(.GSRI(1'b1));
 always #10 clk=~clk;
 piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem")) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(1'b1),.uart_tx(),.hdmi_hpd(1'b1),
  .HP_BCK(a[2]),.HP_WS(a[1]),.HP_DIN(a[0]),.PA_EN(pa1),.knob_sda(sda1),.knob_scl(scl1),
  .tmds_data_p(),.tmds_data_n(),.tmds_clk_p(),.tmds_clk_n());
 // Enabling the optional brightness parameter must not reclaim KEY1 from octave mode.
 piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.ENABLE_BRIGHTNESS(1)) baseline(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(1'b1),.uart_tx(),
  .HP_BCK(b[2]),.HP_WS(b[1]),.HP_DIN(b[0]),.PA_EN(pa2),.knob_sda(sda2),.knob_scl(scl2));
 integer samples=0,nonzero=0,cycles=0;
 always @(posedge clk)begin
  #1;cycles=cycles+1;
  if(rst && dut.core_ready)begin
   if({a,pa1}!=={b,pa2})begin $display("FAIL HDMI octave audio isolation");$finish;end
   if(dut.u_core.output_sample_valid)begin samples=samples+1;if(dut.audio_sample!=0)nonzero=nonzero+1;end
   if(samples>4 && (dut.u_core.sample_underrun || dut.u_core.g_modal.core_overrun))begin $display("FAIL HDMI octave deadline");$finish;end
  end
 end
 task frames;input integer count;integer start;
  begin start=samples;wait(samples>=start+count);@(negedge clk);end
 endtask
 task key_range;input [1:0] expected;
  begin
   bk[0]=0;frames(160);bk[0]=1;frames(160);
   if(dut.current_octave!==expected || baseline.u_core.monitor_octave!==expected)
    begin $display("FAIL formal default octave debounce");$finish;end
  end
 endtask
 task visible_range;input [1:0] expected;integer tries;
  begin
   tries=0;
   while(dut.u_display.state_frame[37:36]!==expected && tries<1200)begin frames(1);tries=tries+1;end
   if(dut.u_display.state_frame[37:36]!==expected)begin $display("FAIL range did not reach HDMI frame");$finish;end
  end
 endtask
 initial begin
  force dut.knob_value_flat={7'd64,7'd32};force baseline.knob_value_flat={7'd64,7'd32};
  force dut.knob_valid=1'b1;force baseline.knob_valid=1'b1;
  force dut.param_ready=1'b1;force baseline.param_ready=1'b1;
  force dut.param_fault=1'b0;force baseline.param_fault=1'b0;
  #105;rst=1;wait(dut.display_reset);frames(120);visible_range(1);
  // A 1ms bounce is below the actual 2ms debounce setting.
  bk[0]=0;frames(48);bk[0]=1;frames(120);
  if(dut.current_octave!=1)begin $display("FAIL formal bounce changed range");$finish;end
  key_range(2);keys[0]=0;frames(120);visible_range(2);
  if(dut.piano_held_keys!==1 || dut.u_core.voice_note_flat[6:0]!=72)
   begin $display("FAIL HDMI high piano note");$finish;end
  // Hold KEY1 beyond the old 0.5s brightness timer is unnecessary: no repeat timer exists.
  key_range(0);visible_range(0);
  if(dut.piano_held_keys!==0 || dut.u_core.voice_note_flat[6:0]!=72)
   begin $display("FAIL HDMI held high note changed");$finish;end
  keys[0]=1;bk[1]=0;frames(160);bk[1]=1;frames(160);keys[4]=0;frames(120);
  if(!dut.instrument_guitar || dut.guitar_held_keys!==13'h10)
   begin $display("FAIL HDMI low guitar display");$finish;end
  key_range(1);visible_range(1);
  if(dut.u_display.state_frame[39]!==1)begin $display("FAIL HDMI instrument status");$finish;end
  if(nonzero<1000)begin $display("FAIL HDMI octave vacuous audio");$finish;end
  $display("PASS tb_hdmi_octaves: actual 2ms debounce, low/middle/high frame state, both instruments, held-note ownership, brightness priority, %0d matching audio samples",samples);$finish;
 end
 initial begin #160000000;$display("FAIL HDMI octave timeout");$finish;end
endmodule
