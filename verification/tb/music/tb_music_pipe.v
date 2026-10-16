`timescale 1ns/1ps
module tb_music_pipe;
 reg clk=0,rst=0,request=0;
 reg [15:0] gate=0,trigger=0,preset=0,accepted_preset;
 wire [3:0] selected_old,selected4,selected4_legacy;wire [15:0] selected16,selected16_legacy;
 wire signed [15:0] sample4_legacy,sample16_legacy;
 wire valid4_legacy,valid16_legacy;wire [3:0] active4_legacy;wire [15:0] active16_legacy;
 wire [67:0] env4_legacy;wire [271:0] env16_legacy;
 reg [111:0] notes=0,velocity=0;
 wire signed [15:0] sample_old,sample4,sample16;
 wire valid_old,valid4,valid16,busy16,overrun16;
 wire [3:0] active_old,active4;
 wire [15:0] active16;
 wire [67:0] env_old,env4;
 wire [271:0] env16;
 integer i,k,t,epoch,fd,count4=0,count16=0,count_old=0;
 reg [15:0] old_hold,pipe_hold,accepted_trigger;
 reg [255:0] individual;reg [63:0] individual4;
 reg [8191:0] capture;
 always #10 clk=~clk;
 voice_bank_music_pipe #(.VOICES(4)) u_four(.voice_instrument(preset[3:0]),.instrument_active(selected4),.global_gain_q16(17'd65536),.pitch_ratio_q16(17'd65536),.clk(clk),.rst_n(rst),.sample_request(request),.voice_gate(gate[3:0]),
 .voice_retrigger(trigger[3:0]),.voice_note_flat(notes[27:0]),.voice_velocity_flat(velocity[27:0]),
 .sample_data(sample4),.sample_valid(valid4),.voice_active(active4),.env_level_flat(env4),.release_done(),.sounding(),.busy(),.sample_clipped(),.overrun());
 voice_bank_music_pipe #(.VOICES(16)) u_sixteen(.voice_instrument(preset),.instrument_active(selected16),.global_gain_q16(17'd65536),.pitch_ratio_q16(17'd65536),.clk(clk),.rst_n(rst),.sample_request(request),.voice_gate(gate),
 .voice_retrigger(trigger),.voice_note_flat(notes),.voice_velocity_flat(velocity),
 .sample_data(sample16),.sample_valid(valid16),.voice_active(active16),.env_level_flat(env16),
 .busy(busy16),.overrun(overrun16),.release_done(),.sounding(),.sample_clipped());
 voice_bank_music_pipe #(.VOICES(4),.SHAPER_ROM_FILE("build/regression/music/rock_v2_legacy_shaper.mem")) u_four_legacy(.voice_instrument(preset[3:0]),.instrument_active(selected4_legacy),.global_gain_q16(17'd65536),.pitch_ratio_q16(17'd65536),.clk(clk),.rst_n(rst),.sample_request(request),.voice_gate(gate[3:0]),
 .voice_retrigger(trigger[3:0]),.voice_note_flat(notes[27:0]),.voice_velocity_flat(velocity[27:0]),
 .sample_data(sample4_legacy),.sample_valid(valid4_legacy),.voice_active(active4_legacy),.env_level_flat(env4_legacy),.release_done(),.sounding(),.busy(),.sample_clipped(),.overrun());
 voice_bank_music_pipe #(.VOICES(16),.SHAPER_ROM_FILE("build/regression/music/rock_v2_legacy_shaper.mem")) u_sixteen_legacy(.voice_instrument(preset),.instrument_active(selected16_legacy),.global_gain_q16(17'd65536),.pitch_ratio_q16(17'd65536),.clk(clk),.rst_n(rst),.sample_request(request),.voice_gate(gate),
 .voice_retrigger(trigger),.voice_note_flat(notes),.voice_velocity_flat(velocity),
 .sample_data(sample16_legacy),.sample_valid(valid16_legacy),.voice_active(active16_legacy),.env_level_flat(env16_legacy),
 .busy(),.overrun(),.release_done(),.sounding(),.sample_clipped());
 initial begin
  if(!$value$plusargs("CAPTURE=%s",capture))capture="build/regression/music/pipe.csv";
  fd=$fopen(capture,"w");if(!fd)begin $display("FAIL: capture open"); $finish; end
  $fdisplay(fd,"epoch,index,gate,trigger,preset,notes,velocity,sample,active,selected,env,voices,sample4,active4,selected4,env4,voices4,legacy_sample,legacy_sample4");
  for(epoch=0;epoch<2;epoch=epoch+1)begin
   rst=0;request=0;gate=0;trigger=0;preset=0;repeat(5)@(negedge clk);rst=1;
   if(overrun16!==0)begin $display("FAIL: overrun reset"); $finish; end
   for(k=0;k<16;k=k+1)begin notes[k*7+:7]=48+k*2;velocity[k*7+:7]=100;end
   for(i=0;i<(epoch==0?11000:400);i=i+1)begin
    trigger=0;
    if(i==10)gate=16'hffff;
    if(i==300)begin trigger=16'hffff;preset=16'hffff;end
    if(i==500)preset=0; // Held piano notes must not change.
    if(i==700)begin gate=16'h5555;end
    if(i==800)begin gate=16'hffff;trigger=16'haaaa;end
    if(i==1300)begin for(k=0;k<16;k=k+1)notes[k*7+:7]=60;trigger=16'hffff;end
    if(i==1800)begin preset=16'hffff; for(k=0;k<16;k=k+1)begin notes[k*7+:7]=k*8;velocity[k*7+:7]=(k==0)?0:127;end trigger=16'hffff;end
    if(i==2300)begin preset=16'haaaa; for(k=0;k<16;k=k+1)begin notes[k*7+:7]=48+k*2;velocity[k*7+:7]=100;end trigger=16'hffff;end
    if(i>2600 && i<5000 && i%37==0)begin
     k=(i/37)%16;notes[k*7+:7]=48+(i%37);trigger[k]=1;gate[k]=1;
    end
    if(i>2700 && i<4900 && i%61==0)gate[(i/61)%16]=0;
    if(i==5500)gate=0;
    accepted_trigger=trigger;accepted_preset=preset;
    // A trigger between sample requests must retain its preset even if the
    // input selector changes again before the next request.
    if(i==3200)begin
     preset=0;trigger=16'hffff;repeat(2)@(negedge clk);trigger=0;preset=16'hffff;
     accepted_trigger=16'hffff;accepted_preset=0;
    end
    request=1;@(negedge clk);request=0;trigger=0;
    for(t=1;t<=1040;t=t+1)begin
     @(negedge clk);
     if(valid4!==valid4_legacy || valid16!==valid16_legacy)begin $display("FAIL: classic latency changed");$finish;end
     if(valid4)begin
      if(t!=251)begin $display("FAIL: pipe4 latency %0d",t); $finish; end
      if({active4,selected4,env4}!=={active4_legacy,selected4_legacy,env4_legacy})begin $display("FAIL: classic four voice state");$finish;end
      for(k=0;k<4;k=k+1)if(u_four.last_voice[k]!==u_four_legacy.last_voice[k])begin $display("FAIL: classic four voice output");$finish;end
      pipe_hold=sample4;count4=count4+1;
     end
     if(valid16)begin
      if(t!=923)begin $display("FAIL: pipe16 latency %0d",t); $finish; end
      if({active16,selected16,env16}!=={active16_legacy,selected16_legacy,env16_legacy})begin $display("FAIL: classic sixteen voice state");$finish;end
      for(k=0;k<16;k=k+1)if(u_sixteen.last_voice[k]!==u_sixteen_legacy.last_voice[k])begin $display("FAIL: classic sixteen voice output");$finish;end
      if(epoch==0 && i>=400 && i<700 && (sample16!==sample16_legacy || sample4!==sample4_legacy))begin $display("FAIL: classic piano-only mix changed");$finish;end
      for(k=0;k<16;k=k+1)individual[k*16+:16]=u_sixteen.last_voice[k];
      for(k=0;k<4;k=k+1)individual4[k*16+:16]=u_four.last_voice[k];
      $fdisplay(fd,"%0d,%0d,%h,%h,%h,%h,%h,%0d,%h,%h,%h,%h,%0d,%h,%h,%h,%h,%0d,%0d",epoch,i,gate,accepted_trigger,accepted_preset,notes,velocity,sample16,active16,selected16,env16,individual,sample4,active4,selected4,env4,individual4,sample16_legacy,sample4_legacy);
      count16=count16+1;
     end
    end
    if(busy16 || overrun16)begin $display("FAIL: sample budget"); $finish; end
   end
   // Busy request must be rejected and flagged; no second output may be queued.
   request=1;@(negedge clk);request=0;repeat(20)@(negedge clk);
   request=1;@(negedge clk);request=0;repeat(20)@(negedge clk);
   if(!overrun16)begin $display("FAIL: busy request not flagged"); $finish; end
   // Reset deliberately interrupts this unfinished frame, then epoch 1 proves restart.
  end
  $fclose(fd);
  if(count4!=11400 || count16!=11400)begin $display("FAIL: capture count"); $finish; end
  $display("PASS tb_music_pipe: 11400 four-voice oracle captures, 11400 sixteen-voice captures, R251/R923, reset/overrun, legacy A/B voice-state and piano isolation");$finish;
 end
 initial begin #300000000;begin $display("FAIL: pipe timeout"); $finish; end end
endmodule
