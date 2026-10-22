`timescale 1ns/1ps
// Accelerated normalized audio injection checks the complete PA/tail policy.
// Delay lengths are sample counts, not changed coefficients; this is NOT a latency test.
module tb_reverb_pa;
 reg clk=0,rst=0,inject_valid=0;
 reg signed [15:0] inject_sample=0;
 wire pa;
 always #10 clk=~clk;
 instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.ENABLE_REVERB(1)) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(2'b11),.piano_key_n(13'h1fff),.uart_rx(1'b1),.uart_tx(),
  .HP_BCK(),.HP_WS(),.HP_DIN(),.PA_EN(pa),.knob_value_flat(14'd0),.knob_valid(1'b0),
  .param_ready(1'b0),.param_fault(1'b0),.control_sustain(1'b0),.control_octave(2'd1),
  .control_ready(),.control_brightness(7'd127));
 integer n,active_count=0,gaps=0,late=0,drains;
 initial begin
  force dut.tone_sample_valid=inject_valid;force dut.tone_sample_data=inject_sample;
  force dut.sounding=1'b0;
  repeat(8)@(negedge clk);rst=1;wait(dut.audio_ready);
  for(n=0;n<45000;n=n+1)begin
   @(negedge clk);inject_valid=1;inject_sample=(n==0)?32767:0;
   @(negedge clk);inject_valid=0;
   wait(dut.output_sample_valid);repeat(3)@(negedge clk);
   if(dut.reverb_tail)begin
    active_count=active_count+1;
    if(pa!==0)begin $display("FAIL PA muted inside wet tail sample %0d",n);$finish;end
    if(dut.output_sample_data==0)gaps=gaps+1;
   end
   if(n>1499 && dut.output_sample_data!=0)late=late+1;
  end
  if(dut.reverb_tail || dut.output_sample_data!=0 || active_count<40000 || gaps<1000 || late<1000)
   begin $display("FAIL PA finite tail/coverage");$finish;end
  // Drain actual frame boundaries after the accelerated tail has become zero.
  drains=0;while(drains<5)begin @(posedge clk);if(dut.output_frame_start)drains=drains+1;end
  repeat(4)@(negedge clk);
  if(pa!==1)begin $display("FAIL PA never returns to quiet");$finish;end
  $display("PASS tb_reverb_pa: active=%0d silent-gap=%0d late=%0d; PA held through delay gaps, then zero and muted after real DAC drain",active_count,gaps,late);$finish;
 end
 initial begin #30000000;$display("FAIL reverb PA timeout");$finish;end
endmodule
