`timescale 1ns/1ps
// Old serial algorithm remains a slow functional oracle; 32-voice DUT also runs
// separately at the real 1041/1042-clock cadence below.
module tb_dual16_core;
 GSR GSR(.GSRI(1'b1));
 reg clk=0,rst=0,req=0,ref_req=0;
 always #10 clk=~clk;
 reg [31:0] gate=0,trig=0,preset=32'hffffffff;
 reg [223:0] notes=0,velocities=0;
 reg [16:0] gain=65536,ratio=65536;
 wire busy,valid,clipped,overrun,ref_valid,ref_clip;
 wire signed [15:0] pcm,ref_pcm;
 wire [31:0] active,done;
 voice_bank_modal_dispatch #(.VOICES(32)) dut(.clk(clk),.rst_n(rst),.sample_request(req),
  .global_gain_q16(gain),.pitch_ratio_q16(ratio),.voice_gate(gate),.voice_retrigger(trig),
  .voice_instrument(preset),.voice_note_flat(notes),.voice_velocity_flat(velocities),
  .voice_active(active),.release_done(done),.instrument_active(),.env_level_flat(),
  .sounding(),.busy(busy),.sample_data(pcm),.sample_valid(valid),.sample_clipped(clipped),.overrun(overrun));
 // Frozen f314bc0 source is materialized and hashed by the test runner.
 voice_bank_music_serial_reference #(.VOICES(32)) reference(.clk(clk),.rst_n(rst),.sample_request(ref_req),
  .global_gain_q16(gain),.pitch_ratio_q16(ratio),.voice_gate(gate),.voice_retrigger(trig),
  .voice_instrument(preset),.voice_note_flat(notes),.voice_velocity_flat(velocities),
  .voice_active(),.release_done(),.instrument_active(),.env_level_flat(),
  .sounding(),.busy(),.sample_data(ref_pcm),.sample_valid(ref_valid),.sample_clipped(ref_clip),.overrun());
 integer cycle=0,issue=0,checked=0,frame,i,heard[0:31],full=0;
 reg [15:0] captured;reg captured_clip;reg compare=1;
 always @(posedge clk)begin
  cycle=cycle+1;if(req && !busy)issue=cycle;
  #1;
  if(rst && valid)begin
   if(cycle-issue!=925)begin $display("FAIL dual16 latency %0d",cycle-issue);$finish;end
   captured=pcm;captured_clip=clipped;
   if(active==32'hffffffff)full=full+1;
   for(i=0;i<32;i=i+1)if(dut.last_voice[i]!=0)heard[i]=heard[i]+1;
  end
  if(rst && ref_valid && compare)begin
   if({captured_clip,captured}!=={ref_clip,ref_pcm})begin
    $display("FAIL dual16 PCM frame=%0d got=%0d ref=%0d",checked,$signed(captured),ref_pcm);$finish;end
   for(i=0;i<32;i=i+1)if(dut.last_voice[i]!==reference.last_voice[i])begin
    $display("FAIL dual16 voice=%0d frame=%0d got=%0d ref=%0d",i,checked,dut.last_voice[i],reference.last_voice[i]);$finish;end
   checked=checked+1;
  end
 end
 task tick;
  input integer clocks;
  begin @(negedge clk);req=1;ref_req=compare;@(negedge clk);req=0;ref_req=0;repeat(clocks-1)@(negedge clk);end
 endtask
 initial begin
  for(i=0;i<32;i=i+1)begin notes[i*7+:7]=48+i;velocities[i*7+:7]=60+(i*7)%68;heard[i]=0;end
  repeat(5)@(negedge clk);rst=1;gate=32'hffffffff;
  for(frame=0;frame<1600;frame=frame+1)begin
   if(frame==128)begin preset=32'haaaaaaaa;trig=32'hffffffff;end
   if(frame==129)trig=0;
   if(frame==256)begin preset=0;trig=32'hffffffff;end
   if(frame==257)trig=0;
   if(frame==300)begin
    for(i=0;i<32;i=i+1)notes[i*7+:7]=(i*4);
    trig=32'hffffffff;
   end
   if(frame==301)trig=0;
   if(frame>=320 && frame<384 && (frame%16)==0)begin
    for(i=0;i<32;i=i+1)notes[i*7+:7]=(i*4)+(frame/16)%4;
    preset=~preset;trig=32'hffffffff;
   end
   if(frame>=320 && frame<384 && (frame%16)==1)trig=0;
   if(frame==384)gain=8192;
   if(frame==448)ratio=58386;
   if(frame==512)ratio=73562;
   if(frame==600)begin notes[31*7+:7]=84;trig=32'h80000000;end
   if(frame==601)trig=0;
   if(frame==640)gain=0;
   if(frame==648)begin gain=65536;ratio=65536;end
   if(frame==700)gate=32'h55555555;
   if(frame==850)begin gate=32'hffffffff;preset=32'hffffffff;trig=32'hffffffff;end
   if(frame==851)trig=0;
   if(frame==900)gate=0;
   tick(1900);
  end
  if(checked!=1600 || full<600)begin $display("FAIL dual16 coverage");$finish;end
  for(i=0;i<32;i=i+1)if(heard[i]<100)begin $display("FAIL dual16 inaudible voice %0d",i);$finish;end
  // Reset while RAM contains prior notes, then exercise the real sample budget.
  rst=0;gate=0;trig=0;compare=0;repeat(5)@(negedge clk);rst=1;tick(1042);
  if(pcm!==0)begin $display("FAIL dual16 reset stale RAM");$finish;end
  gate=32'hffffffff;repeat(1000)tick(1042);
  if(overrun)begin $display("FAIL dual16 real-time overrun");$finish;end
  gate=0;repeat(4200)tick(1042);
  if(done!==32'hffffffff || pcm!==0)begin $display("FAIL dual16 tails release");$finish;end
  @(negedge clk);req=1;@(negedge clk);req=0;repeat(10)@(negedge clk);req=1;
  @(negedge clk);req=0;repeat(3)@(negedge clk);
  if(!overrun)begin $display("FAIL dual16 overrun flag");$finish;end
  rst=0;repeat(5)@(negedge clk);rst=1;tick(1042);
  if(overrun || pcm!==0)begin $display("FAIL dual16 recovery");$finish;end
  $display("PASS tb_dual16_core: 1600 exact PCM/32 voice comparisons, 5200 real-time frames, R925, all 32 audible, reset/tails/overrun");$finish;
 end
 initial begin #220000000;$display("FAIL dual16 timeout");$finish;end
endmodule
