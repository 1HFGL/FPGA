`timescale 1ns/1ps
// Change controls immediately AFTER acceptance, then pulse a retrigger while
// busy. Registered envelope enables must use R0's complete input snapshot.
module tb_dual16_snapshot;
 reg clk=0,rst=0,req=0;
 always #10 clk=~clk;
 GSR GSR(.GSRI(1'b1));
 reg [31:0] gate=0,trig=0,preset=0;
 reg [223:0] notes=0,velocity=0;
 reg [16:0] gain=65536,ratio=65536;
 wire valid,ref_valid,clip,ref_clip;
 wire signed [15:0] pcm,ref_pcm;
 wire overrun;
 reg [16:0] captured;
 integer frame,i,checked=0;
 voice_bank_modal_dispatch #(.VOICES(32)) dut(
  .clk(clk),.rst_n(rst),.sample_request(req),.global_gain_q16(gain),.pitch_ratio_q16(ratio),
  .voice_gate(gate),.voice_retrigger(trig),.voice_instrument(preset),
  .voice_note_flat(notes),.voice_velocity_flat(velocity),.voice_active(),.release_done(),
  .instrument_active(),.env_level_flat(),.sounding(),.busy(),.sample_data(pcm),
  .sample_valid(valid),.sample_clipped(clip),.overrun(overrun));
 voice_bank_music_serial_reference #(.VOICES(32)) reference(
  .clk(clk),.rst_n(rst),.sample_request(req),.global_gain_q16(gain),.pitch_ratio_q16(ratio),
  .voice_gate(gate),.voice_retrigger(trig),.voice_instrument(preset),
  .voice_note_flat(notes),.voice_velocity_flat(velocity),.voice_active(),.release_done(),
  .instrument_active(),.env_level_flat(),.sounding(),.busy(),.sample_data(ref_pcm),
  .sample_valid(ref_valid),.sample_clipped(ref_clip),.overrun());
 always @(posedge clk)begin
  #1;
  if(rst && valid)captured={clip,pcm};
  if(rst && ref_valid)begin
   if(captured!=={ref_clip,ref_pcm})begin $display("FAIL dual16 snapshot PCM frame=%0d",frame);$finish;end
   for(i=0;i<32;i=i+1)if(dut.last_voice[i]!==reference.last_voice[i])begin
    $display("FAIL dual16 snapshot voice=%0d frame=%0d",i,frame);$finish;end
   checked=checked+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(frame=0;frame<256;frame=frame+1)begin
   gate=32'hffffffff;trig=(frame%32==0)?32'hffffffff:0;
   preset=(frame<128)?32'haaaa5555:32'h5555aaaa;
   gain=(frame%7==0)?8192:65536;ratio=(frame%11==0)?58386:65536;
   for(i=0;i<32;i=i+1)begin notes[i*7+:7]=36+i+(frame/64)*12;velocity[i*7+:7]=70+i;end
   req=1;@(negedge clk);req=0;
   // Exactly between R0 and R1: external values must not alter this frame.
   gate=0;trig=0;preset=~preset;notes=0;velocity=0;gain=0;ratio=73562;
   repeat(8)@(negedge clk);
   trig=32'h80010001;@(negedge clk);trig=0;
   preset=~preset;
   repeat(1890)@(negedge clk);
  end
  if(checked!=256 || overrun)begin $display("FAIL dual16 snapshot coverage/overrun");$finish;end
  $display("PASS tb_dual16_snapshot: 256 exact PCM/32 voice comparisons after R0 control changes and busy retriggers");$finish;
 end
 initial begin #11000000;$display("FAIL dual16 snapshot timeout");$finish;end
endmodule
