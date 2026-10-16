`timescale 1ns/1ps
module tb_music_controls;
 reg clk=0,rst=0,request=0,control_valid=0;
 reg [6:0] volume=127;reg [10:0] bend=512;
 wire [6:0] target_volume;wire [10:0] target_bend,bend_current;
 wire [16:0] gain,ratio;reg [16:0] captured_gain,captured_ratio;
 reg [15:0] gate=0,trigger=0,preset=16'haaaa,captured_trigger;
 reg [111:0] notes=0,velocity=0;
 wire [15:0] active,selected;wire [271:0] env;
 wire signed [15:0] sample;wire valid,busy,overrun,clipped,sounding;
 reg [255:0] individuals;
 reg [8191:0] path;
 integer i,k,t,epoch,fd,count=0,outputs;
 always #10 clk=~clk;
 music_controls controls(.clk(clk),.rst_n(rst),.sample_request(request),.control_valid(control_valid),
  .control_volume(volume),.control_bend(bend),.target_volume(target_volume),.target_bend(target_bend),
  .gain_q16(gain),.bend_current(bend_current),.pitch_ratio_q16(ratio));
 voice_bank_music_pipe bank(.clk(clk),.rst_n(rst),.sample_request(request),
  .global_gain_q16(gain),.pitch_ratio_q16(ratio),.voice_gate(gate),.voice_retrigger(trigger),
  .voice_instrument(preset),.voice_note_flat(notes),.voice_velocity_flat(velocity),
  .voice_active(active),.release_done(),.instrument_active(selected),.env_level_flat(env),
  .sample_data(sample),.sample_valid(valid),.sample_clipped(clipped),.sounding(sounding),.busy(busy),.overrun(overrun));
 task packet;input [6:0] v;input [10:0] b;
 begin volume=v;bend=b;control_valid=1;@(negedge clk);control_valid=0;@(negedge clk);end endtask
 initial begin
  if(!$value$plusargs("CAPTURE=%s",path))path="build/regression/music/controls.csv";
  fd=$fopen(path,"w");if(!fd)begin $display("FAIL controls capture");$finish;end
  $fdisplay(fd,"epoch,index,gate,trigger,preset,notes,velocity,gain,ratio,volume,bend,bend_current,sample,active,selected,env,voices");
  for(epoch=0;epoch<2;epoch=epoch+1)begin
   rst=0;request=0;control_valid=0;gate=0;trigger=0;preset=16'haaaa;
   repeat(5)@(negedge clk);rst=1;repeat(3)@(negedge clk);
   for(k=0;k<16;k=k+1)begin notes[k*7+:7]=48+k*2;velocity[k*7+:7]=100;end
   for(i=0;i<(epoch==0?6000:1500);i=i+1)begin
    trigger=0;
    if(i==10)gate=16'hffff;
    if(i==30)begin packet(12,2047);if(target_volume!=8 || target_bend!=512)begin $display("FAIL invalid pair not atomic");$finish;end end
    if(i==100)packet(64,1024);
    if(i==300)packet(0,0);
    if(i==500)packet(127,512);
    if(i==700)begin trigger=16'hffff;preset=16'hffff;end
    if(i==900)packet(127,1024);
    if(i>1100 && i<1200 && i%7==0)packet(i%128,(i*17)%1025);
    if(i==1200)gate=16'h5555;
    if(i==1250)packet(33,0);
    if(i==1400)begin trigger=16'hffff;gate=16'hffff;preset=0;end
    if(i==1450)begin trigger=16'h0001;preset=1;end
    if(i==1500)begin gate=0;packet(127,1024);end
    if(i==1600)packet(64,0);
    captured_gain=gain;captured_ratio=ratio;captured_trigger=trigger;outputs=0;
    $fwrite(fd,"%0d,%0d,%h,%h,%h,%h,%h,%0d,%0d,%0d,%0d,%0d,",epoch,i,gate,trigger,preset,notes,velocity,gain,ratio,target_volume,target_bend,bend_current);
    request=1;@(negedge clk);request=0;trigger=0;
    // Attempt to change raw controls while the bank runs. The frame uses its snapshot.
    if(i==950)packet(0,0);
    for(t=(i==950?3:1);t<=1040;t=t+1)begin
     @(negedge clk);
     if(valid)begin
      if(t!=923 || clipped || overrun)begin $display("FAIL controls deadline %0d",t);$finish;end
      if(bank.gain_latched!==captured_gain || bank.ratio_latched!==captured_ratio)begin $display("FAIL torn frame controls");$finish;end
      for(k=0;k<16;k=k+1)individuals[k*16+:16]=bank.last_voice[k];
      $fdisplay(fd,"%0d,%h,%h,%h,%h",sample,active,selected,env,individuals);
      if(i>=440 && i<490 && (sample!==0 || active!==16'hffff || !sounding))begin $display("FAIL mute killed voices or leaked audio");$finish;end
      count=count+1;outputs=outputs+1;
     end
    end
    if(outputs!=1 || busy || overrun)begin $display("FAIL sample count/budget");$finish;end
   end
   // Reset in the middle of a pitch/volume ramp and a bank operation.
   packet(0,0);request=1;@(negedge clk);request=0;repeat(20)@(negedge clk);
  end
  $fclose(fd);if(count!=7500)begin $display("FAIL controls coverage");$finish;end
  $display("PASS tb_music_controls: 7500 frames, full16 mixed presets, mute/unmute, held/new/tail bend, atomic snapshots, reset");$finish;
 end
 initial begin #200000000;$display("FAIL controls timeout");$finish;end
endmodule
