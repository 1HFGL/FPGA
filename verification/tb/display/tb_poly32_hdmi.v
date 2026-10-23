`timescale 1ns/1ps
// Real formal tops, real 48 kHz request/DAC cadence, shared 32 voices.
// ADC values are injected at the existing normalized boundary, not a physical ADC test.
module tb_poly32_hdmi;
 reg clk=0,rst=0,hpd=1,rx=1,kv=0;
 reg [1:0] bk=3;
 reg [12:0] keys=13'h1fff;
 reg [13:0] knobs={7'd64,7'd32};
 tri1 sda1,sda2;
 wire [4:0] audio1,audio2;
 GSR GSR(.GSRI(1'b1));
 always #10 clk=~clk;
 piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
  .DISPLAY_LOCK_CYCLES(8),.UART_CLKS_PER_BIT(16)) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.uart_tx(audio1[4]),.hdmi_hpd(hpd),
  .HP_BCK(audio1[3]),.HP_WS(audio1[2]),.HP_DIN(audio1[1]),.PA_EN(audio1[0]),.knob_sda(sda1),.knob_scl(),
  .tmds_data_p(),.tmds_data_n(),.tmds_clk_p(),.tmds_clk_n());
 piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16)) baseline(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.uart_tx(audio2[4]),
  .HP_BCK(audio2[3]),.HP_WS(audio2[2]),.HP_DIN(audio2[1]),.PA_EN(audio2[0]),.knob_sda(sda2),.knob_scl());
 integer samples=0,since_reset=0,cycle=0,issue=0,fd,words=0,bits=0,nonzero=0,tail_only=0,epoch=0;
 integer i,heard[0:31],full32=0;
 reg [15:0] word=0,pending=0,active=0;
 reg pending_valid=0;
 reg signed [15:0] dry_capture,chorus_capture,delay_capture;
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!dut.core_ready)begin since_reset=0;pending_valid=0;pending=0;active=0;end
  else begin
   if(dut.u_core.sample_request)begin since_reset=since_reset+1;issue=cycle;end
   if(since_reset>4 && (dut.u_core.sample_underrun || baseline.u_core.sample_underrun ||
    dut.u_core.g_modal.core_overrun || dut.u_core.tone_overrun || dut.u_core.chorus_overrun || dut.u_core.delay_overrun ||
    baseline.u_core.chorus_overrun || baseline.u_core.delay_overrun || dut.u_core.reverb_overrun || baseline.u_core.reverb_overrun))
    begin $display("FAIL effects deadline/overrun");$finish;end
   if(dut.u_core.tone_sample_valid)dry_capture=dut.u_core.tone_sample_data;
   if(dut.u_core.chorus_sample_valid)chorus_capture=dut.u_core.chorus_sample_data;
   if(dut.u_core.delay_sample_valid)delay_capture=dut.u_core.delay_sample_data;
   if(dut.u_core.output_frame_start)begin active<=pending_valid?pending:16'd0;pending_valid<=0;end
   if(baseline.u_core.output_sample_valid && cycle-issue!=830)begin $display("FAIL no-screen R830");$finish;end
   if(dut.u_core.output_sample_valid)begin
    if(cycle-issue!=833)begin $display("FAIL wet R833 got=%0d",cycle-issue);$finish;end
    samples=samples+1;pending<=dut.u_core.output_sample_data;pending_valid<=1;
    if(fd!=0)$fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d\n",epoch,dry_capture,chorus_capture,delay_capture,$signed(dut.u_core.output_sample_data),dut.u_core.voice_count);
    if(dut.u_core.output_sample_data!=0)begin nonzero=nonzero+1;if(dry_capture==0)tail_only=tail_only+1;end
    if(dut.u_core.voice_count==32)full32=full32+1;
    for(i=0;i<32;i=i+1)if(dut.u_core.g_modal.u_bank.u_modal.last_voice[i]!=0)heard[i]=heard[i]+1;
   end
  end
  #1;
  // Synthesis latency differs by three clocks, but actual DAC frame words coincide.
  if(rst && audio1!==audio2)begin $display("FAIL wet HDMI/no-screen pin difference at %0d",cycle);$finish;end
 end
 always @(posedge audio1[3])if(dut.core_ready)begin
  word={word[14:0],audio1[1]};bits=bits+1;
  if(bits==16)begin bits=0;words=words+1;
   if(word!==active)begin $display("FAIL wet serial DAC got=%h expected=%h",word,active);$finish;end
  end
 end
 task frames;input integer count;integer start;
  begin start=samples;wait(samples>=start+count);@(negedge clk);end
 endtask
 task key;input integer k;
  begin bk[k]=0;repeat(100)@(negedge clk);bk[k]=1;repeat(100)@(negedge clk);end
 endtask
 task knob;input [6:0] v,b;
  begin @(negedge clk);knobs={b,v};kv=1;@(negedge clk);kv=0;frames(150);end
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
  for(i=0;i<32;i=i+1)heard[i]=0;
  fd=$fopen("build/regression/poly32/hdmi_audio.csv","w");$fwrite(fd,"epoch,dry,chorus,delay,wet,voices\n");
  force dut.knob_value_flat=knobs;force baseline.knob_value_flat=knobs;
  force dut.knob_valid=kv;force baseline.knob_valid=kv;
  force dut.param_ready=1'b1;force baseline.param_ready=1'b1;
  force dut.param_fault=1'b0;force baseline.param_fault=1'b0;
  repeat(8)@(negedge clk);rst=1;wait(dut.core_ready);knob(32,64);
  if(dut.brightness_current!=127 || dut.touch_available)begin $display("FAIL wet startup controls");$finish;end
  keys=0;send("HELLO\n");
  send("NOTE_ON 73 100 0\n");send("NOTE_ON 74 100 0\n");send("NOTE_ON 75 100 0\n");send("NOTE_ON 76 100 0\n");send("NOTE_ON 77 100 0\n");send("NOTE_ON 78 100 0\n");send("NOTE_ON 79 100 0\n");send("NOTE_ON 80 100 0\n");send("NOTE_ON 81 100 0\n");send("NOTE_ON 82 100 0\n");send("NOTE_ON 83 100 0\n");send("NOTE_ON 84 100 0\n");send("NOTE_ON 85 100 0\n");send("NOTE_ON 86 100 0\n");send("NOTE_ON 87 100 0\n");send("NOTE_ON 88 100 0\n");send("NOTE_ON 89 100 0\n");send("NOTE_ON 90 100 0\n");send("NOTE_ON 91 100 0\n");frames(1800);
  if(dut.u_core.voice_count!=32)begin $display("FAIL wet full32");$finish;end
  for(i=0;i<32;i=i+1)if(heard[i]<10)begin $display("FAIL wet inaudible voice %0d",i);$finish;end
  // The 33rd independent note must steal one slot, never wrap the count to zero.
  send("NOTE_ON 92 100 0\n");frames(2);
  if(dut.u_core.voice_count!=32 || dut.u_core.steal_count!=1)begin $display("FAIL 33rd voice steal");$finish;end
  key(0);key(1);keys[3:0]=15;frames(3);keys[3:0]=0;frames(2400);
  if(dut.current_octave!=2 || !dut.instrument_guitar || dut.guitar_held_keys[3:0]!=15)
   begin $display("FAIL wet range/mode/new note");$finish;end
  hpd=0;frames(20);hpd=1;force dut.pll_locked=1'b0;frames(20);release dut.pll_locked;
  force dut.pixel_clk=1'b0;frames(20);release dut.pixel_clk;
  knob(16,0);
  if(dut.volume!=16 || dut.bend!=-32768)begin $display("FAIL wet knobs");$finish;end
  // Isolate a now-silent source while retaining real delay RAM and actual DAC cadence.
  // The separate PA test drains the entire tail; this capture checks audible late energy.
  force dut.u_core.sample_data=16'sd0;force baseline.u_core.sample_data=16'sd0;
  force dut.u_core.sounding=1'b0;force baseline.u_core.sounding=1'b0;
  frames(9000);
  if(!dut.u_core.reverb_tail || audio1[0]!==0 || tail_only<100)begin $display("FAIL wet tail cut/missing");$finish;end
  if(nonzero<3000 || full32<2000)begin $display("FAIL wet coverage");$finish;end
  $fclose(fd);fd=0;
  rst=0;keys=13'h1fff;rx=1;repeat(8)@(negedge clk);
  release dut.u_core.sample_data;release baseline.u_core.sample_data;
  release dut.u_core.sounding;release baseline.u_core.sounding;
  bits=0;word=0;epoch=1;rst=1;frames(20);
  if(dut.u_core.chorus_tail || dut.u_core.delay_tail || dut.u_core.reverb_tail || dut.audio_sample!=0 || audio1[0]!==1 || dut.current_octave!=1 || dut.instrument_guitar)
   begin $display("FAIL wet dirty reset/quiet PA");$finish;end
  $display("PASS tb_poly32_hdmi: R833/R830, full32=%0d, serial words=%0d, wet-only=%0d, both presets/ranges/knobs, video isolation and dirty reset",full32,words,tail_only);$finish;
 end
 initial begin #500000000;$display("FAIL effects HDMI timeout");$finish;end
endmodule
