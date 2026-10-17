`timescale 1ns/1ps
// Actual HDMI top and modal core; future USB host is represented ONLY by normalized reports.
// No assertion here claims physical USB reception or real touch latency.
module tb_touch_hdmi_audio;
 reg clk=0,rst=0,rx=1,kv=0,hpd=1;
 reg [1:0] bk=3;
 reg [12:0] keys=13'h1fff;
 reg [13:0] knobs={7'd64,7'd32};
 reg connected=0,tvalid=0,down=0;
 reg [11:0] tx=0,ty=0;
 tri1 sda;
 wire bck,ws,din,pa;
 GSR GSR(.GSRI(1'b1));
 always #10 clk=~clk;
 piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
  .DISPLAY_LOCK_CYCLES(8),.UART_CLKS_PER_BIT(16)) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.uart_tx(),.hdmi_hpd(hpd),
  .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_sda(sda),.knob_scl(),
  .tmds_data_p(),.tmds_data_n(),.tmds_clk_p(),.tmds_clk_n());
 integer frames=0,since_reset=0,cycle=0,issue=0,fd,words=0,bits=0,nonzero=0,changed=0,n,heard[0:15],i;
 reg [15:0] word=0,pending=0,active=0;
 reg pending_valid=0;
 reg signed [15:0] captured_raw;
 reg [6:0] captured_brightness,previous_brightness;
 reg [16:0] prior_gain;
 reg [17:0] prior_bend;
 reg prior_request;
 reg [111:0] saved_notes;
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!dut.core_ready)since_reset=0;
  if(dut.core_ready)begin
   previous_brightness=dut.brightness_current;prior_request=dut.u_core.sample_request;
   if(dut.u_core.sample_request)begin frames=frames+1;since_reset=since_reset+1;issue=cycle;end
   if(since_reset>4 && (dut.u_core.sample_underrun || dut.u_core.g_modal.core_overrun || dut.u_core.tone_overrun))begin
    $display("FAIL touch audio deadline");$finish;end
   if(dut.u_core.sample_valid)begin captured_raw=dut.u_core.sample_data;captured_brightness=dut.brightness_current;end
   if(dut.u_core.output_frame_start)begin active<=pending_valid?pending:16'd0;pending_valid<=0;end
   if(dut.u_core.output_sample_valid)begin
    if(cycle-issue!=927)begin $display("FAIL touch R927 latency %0d",cycle-issue);$finish;end
    pending<=dut.u_core.output_sample_data;pending_valid<=1;
    if(fd!=0)$fwrite(fd,"%0d,%0d,%0d,%0d,%0d\n",frames,captured_raw,captured_brightness,$signed(dut.u_core.output_sample_data),dut.u_core.voice_count);
    if(dut.u_core.output_sample_data!=0)nonzero=nonzero+1;
    if(captured_brightness==127 && dut.u_core.output_sample_data!==captured_raw)begin $display("FAIL touch bypass");$finish;end
    if(captured_brightness!=127 && dut.u_core.output_sample_data!=captured_raw)changed=changed+1;
    for(i=0;i<16;i=i+1)if(dut.u_core.g_modal.u_bank.u_modal.last_voice[i]!=0)heard[i]=heard[i]+1;
   end
   #1;
   if(!prior_request && dut.brightness_current!==previous_brightness)begin $display("FAIL brightness changed off audio request");$finish;end
   if(dut.brightness_current>previous_brightness+1 || previous_brightness>dut.brightness_current+1)begin $display("FAIL abrupt brightness change");$finish;end
  end
 end
 always @(posedge bck)if(dut.core_ready)begin
  word={word[14:0],din};bits=bits+1;
  if(bits==16)begin bits=0;words=words+1;
   if(word!==active)begin $display("FAIL touch serial DAC got=%h expected=%h",word,active);$finish;end
  end
 end
 task wait_frames;input integer count;integer start;
  begin start=frames;wait(frames>=start+count);@(negedge clk);end
 endtask
 task report;input d;input [11:0] x,y;
  begin @(negedge clk);down=d;tx=x;ty=y;tvalid=1;@(negedge clk);tvalid=0;end
 endtask
 task key;input integer k;
  begin bk[k]=0;repeat(100)@(negedge clk);bk[k]=1;repeat(100)@(negedge clk);end
 endtask
 task knob;input [6:0] v,b;
  begin @(negedge clk);knobs={b,v};kv=1;@(negedge clk);kv=0;wait_frames(150);end
 endtask
 task send;input [511:0] text;integer bytes,a,b,j;
  begin bytes=0;for(j=0;j<64;j=j+1)if(text[j*8+:8]!=0)bytes=j+1;
   for(a=bytes-1;a>=0;a=a-1)begin
    @(negedge clk);rx=0;repeat(16)@(negedge clk);
    for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
    rx=1;repeat(16)@(negedge clk);
   end repeat(40)@(negedge clk);
  end
 endtask
 initial begin
  for(i=0;i<16;i=i+1)heard[i]=0;
  fd=$fopen("build/regression/final/touch_audio.csv","w");$fwrite(fd,"frame,raw,brightness,filtered,voices\n");
  force dut.touch_connected=connected;force dut.touch_report_valid=tvalid;
  force dut.touch_down=down;force dut.touch_x=tx;force dut.touch_y=ty;
  force dut.knob_value_flat=knobs;force dut.knob_valid=kv;
  force dut.param_ready=1'b1;force dut.param_fault=1'b0;
  repeat(8)@(negedge clk);rst=1;wait(dut.core_ready);knob(32,64);
  if(dut.brightness_current!=127 || dut.touch_available)begin $display("FAIL touch startup");$finish;end
  keys[0]=0;wait_frames(300);prior_gain=dut.u_core.master_gain;prior_bend=dut.u_core.bend_ratio;
  connected=1;report(0,0,0);report(1,352,50);wait_frames(150);
  if(dut.brightness_current!=0 || dut.u_core.voice_count!=1 || dut.u_core.master_gain!=prior_gain || dut.u_core.bend_ratio!=prior_bend)
   begin $display("FAIL touch independence");$finish;end
  key(0);key(1);wait_frames(10);
  if(dut.current_octave!=2 || !dut.instrument_guitar || dut.brightness_current!=0 || dut.u_core.voice_note_flat[6:0]!=60)
   begin $display("FAIL touch preserved KEY1/KEY2/held pitch");$finish;end
  keys[4]=0;wait_frames(150);
  if(dut.guitar_held_keys!=13'h10)begin $display("FAIL touch guitar note");$finish;end
  report(1,608,50);wait_frames(80);
  if(dut.brightness_current!=64)begin $display("FAIL drag midpoint");$finish;end
  saved_notes=dut.u_core.voice_note_flat;knob(16,127);
  if(dut.brightness_current!=64 || dut.u_core.master_gain>=prior_gain || dut.u_core.bend_ratio<=prior_bend || dut.u_core.voice_note_flat!==saved_notes)
   begin $display("FAIL touch independent knobs");$finish;end
  keys=0;send("HELLO\n");send("NOTE_ON 85 100 0\n");send("NOTE_ON 86 100 0\n");send("NOTE_ON 87 100 0\n");wait_frames(200);
  if(dut.u_core.voice_count!=16)begin $display("FAIL touch full16");$finish;end
  for(i=0;i<16;i=i+1)if(heard[i]<10)begin $display("FAIL touch inaudible voice %0d",i);$finish;end
  // Screen disconnect, PLL loss and stalled pixel clock cannot block tone control/audio.
  hpd=0;report(1,352,50);wait_frames(150);hpd=1;
  force dut.pixel_clk=1'b0;report(1,608,50);wait_frames(80);release dut.pixel_clk;
  if(dut.brightness_current!=64)begin $display("FAIL touch waits for video");$finish;end
  force dut.pll_locked=1'b0;wait_frames(10);release dut.pll_locked;
  connected=0;wait_frames(150);
  if(dut.touch_available || dut.brightness_current!=64)begin $display("FAIL touch disconnect changed tone");$finish;end
  connected=1;report(0,0,0);report(1,920,40);wait_frames(150);
  if(dut.brightness_current!=127)begin $display("FAIL touch restore");$finish;end
  report(0,0,0);report(1,352,50);wait_frames(150);
  keys=13'h1fff;send("NOTE_OFF 85 0\n");send("NOTE_OFF 86 0\n");send("NOTE_OFF 87 0\n");wait_frames(7000);
  if(dut.u_core.voice_count!=0 || dut.u_core.tone_tail || dut.u_core.output_sample_data!=0 || pa!==1)
   begin $display("FAIL touch finite release tail");$finish;end
  if(nonzero<1000 || changed<500)begin $display("FAIL touch vacuous audio");$finish;end
  $fclose(fd);fd=0;
  rst=0;repeat(8)@(negedge clk);rst=1;wait_frames(10);
  if(dut.brightness_current!=127 || dut.current_octave!=1 || dut.instrument_guitar)begin $display("FAIL touch reset defaults");$finish;end
  $display("PASS tb_touch_hdmi_audio: full16 mixed presets, independent controls, R927, %0d serial words, %0d altered samples, video isolation and finite tails",words,changed);$finish;
 end
 initial begin #300000000;$display("FAIL touch integrated timeout");$finish;end
endmodule
