`timescale 1ns/1ps
// Formal defaults, real I2C/48kHz, accelerated mechanical debounce and UART only.
module tb_performance_octaves;
 reg clk=0,rst=0,rx=1;
 reg [1:0] bk=3;
 reg [12:0] keys=13'h1fff;
 tri1 sda;
 wire scl,bck,ws,din,pa;
 always #10 clk=~clk;
 piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16)) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.uart_tx(),
  .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_sda(sda),.knob_scl(scl));
 performance_adc_model #(.CONV0(6600),.CONV1(13200)) adc(.scl(scl),.sda(sda));
 integer frames=0,since_reset=0,cycle=0,issue=0,n,k,r,m,base_note,tested=0,words=0,bits=0,nonzero=0;
 reg [15:0] word=0,pending=0,active=0;
 reg pending_valid=0;
 reg [16:0] old_gain;
 reg [17:0] old_bend;
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!dut.core_ready)begin since_reset=0;pending<=0;active<=0;pending_valid<=0;end
  else begin
   if(dut.u_core.sample_request)begin frames=frames+1;since_reset=since_reset+1;issue=cycle;end
   if(dut.u_core.output_frame_start)begin active<=pending_valid?pending:16'd0;pending_valid<=0;end
   if(dut.u_core.output_sample_valid)begin
    if(cycle-issue!=924)begin $display("FAIL octave R924");$finish;end
    if(dut.u_core.output_sample_data!==dut.u_core.sample_data || dut.u_core.brightness_current!==127)
     begin $display("FAIL octave must bypass brightness");$finish;end
    pending<=dut.u_core.output_sample_data;pending_valid<=1;
    if(dut.u_core.output_sample_data!=0)nonzero=nonzero+1;
   end
   if(since_reset>4 && (dut.u_core.sample_underrun || dut.u_core.g_modal.core_overrun || dut.u_core.input_fault))
    begin $display("FAIL octave deadline/overflow");$finish;end
  end
 end
 always @(posedge bck)if(dut.core_ready)begin
  word={word[14:0],din};bits=bits+1;
  if(bits==16)begin bits=0;words=words+1;
   if(word!==active)begin $display("FAIL octave serial PCM %h %h",word,active);$finish;end
  end
 end
 task wait_frames;input integer count;integer start;
  begin start=frames;wait(frames>=start+count);@(negedge clk);end
 endtask
 task press_board;input integer key;
  begin bk[key]=0;wait_frames(3);bk[key]=1;wait_frames(3);end
 endtask
 task select_range;input [1:0] target;integer tries;
  begin
   tries=0;
   while(dut.u_core.monitor_octave!=target && tries<3)begin press_board(0);tries=tries+1;end
   if(dut.u_core.monitor_octave!=target)begin $display("FAIL range cycle target=%0d",target);$finish;end
  end
 endtask
 function integer held;
  input integer source,note,preset;integer j;
  begin held=0;for(j=0;j<16;j=j+1)
   if(dut.u_core.voice_key_down[j] && dut.u_core.voice_source_flat[j*8+:8]==source &&
      dut.u_core.voice_note_flat[j*7+:7]==note && dut.u_core.bank_timbre[j]==preset)held=held+1;
  end
 endfunction
 function integer held_count;
  input integer unused;integer j;
  begin held_count=0;for(j=0;j<16;j=j+1)if(dut.u_core.voice_key_down[j])held_count=held_count+1;end
 endfunction
 task send;input [511:0] text;integer bytes,a,b,j;
  begin
   bytes=0;for(j=0;j<64;j=j+1)if(text[j*8+:8]!=0)bytes=j+1;
   for(a=bytes-1;a>=0;a=a-1)begin
    @(negedge clk);rx=0;repeat(16)@(negedge clk);
    for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
    rx=1;repeat(16)@(negedge clk);
   end repeat(40)@(negedge clk);
  end
 endtask
 initial begin
  repeat(8)@(negedge clk);rst=1;
  wait(dut.param_ready && dut.knob_value_flat=={7'd64,7'd32});wait_frames(70);
  if(dut.u_core.monitor_octave!==1 || dut.u_core.selected_guitar)begin $display("FAIL octave defaults");$finish;end
  old_gain=dut.u_core.master_gain;old_bend=dut.u_core.bend_ratio;
  // Sub-debounce pulse must not change range; long hold must produce just one step.
  bk[0]=0;repeat(3)@(negedge clk);bk[0]=1;wait_frames(3);
  if(dut.u_core.monitor_octave!=1)begin $display("FAIL octave bounce");$finish;end
  bk[0]=0;wait_frames(30);
  if(dut.u_core.monitor_octave!=2 || held_count(0)!=0)begin $display("FAIL octave hold/alias");$finish;end
  bk[0]=1;wait_frames(3);press_board(0);
  if(dut.u_core.monitor_octave!=0)begin $display("FAIL high-low wrap");$finish;end
  press_board(0);
  if(dut.u_core.monitor_octave!=1)begin $display("FAIL low-middle wrap");$finish;end
  for(m=0;m<2;m=m+1)begin
   if(m==1)press_board(1);
   for(r=0;r<3;r=r+1)begin
    select_range(r[1:0]);base_note=48+12*r;
    for(k=0;k<13;k=k+1)begin
     keys[k]=0;wait_frames(8);
     if(held(k,base_note+k,m)!=1 || held_count(0)!=1)begin
      $display("FAIL note map mode=%0d range=%0d key=%0d",m,r,k);$finish;end
     if(dut.u_core.monitor_key_down!==(13'd1<<k) ||
        (m==0 && (dut.u_core.monitor_piano_keys!==(13'd1<<k) || dut.u_core.monitor_guitar_keys!==0)) ||
        (m==1 && (dut.u_core.monitor_guitar_keys!==(13'd1<<k) || dut.u_core.monitor_piano_keys!==0)))
      begin $display("FAIL current-range highlight");$finish;end
     for(n=0;n<16;n=n+1)if(dut.u_core.voice_key_down[n] &&
      (dut.u_core.g_modal.u_bank.u_modal.notes[n*7+:7]!=base_note+k ||
       dut.u_core.g_modal.u_bank.u_modal.instrument_active[n]!=(m==0)))
       begin $display("FAIL modal note/preset differs");$finish;end
     tested=tested+1;keys[k]=1;wait_frames(8);
     if(held_count(0)!=0)begin $display("FAIL scan release");$finish;end
    end
   end
  end
  if(dut.u_core.master_gain!=old_gain || dut.u_core.bend_ratio!=old_bend)
   begin $display("FAIL octave changed knobs");$finish;end
  // Piano C4 held across range and instrument changes. PC C4 has independent ownership.
  press_board(1);select_range(1);keys[0]=0;wait_frames(8);
  send("HELLO\n");send("NOTE_ON 60 100 0\n");wait_frames(8);
  if(held_count(0)!=2)begin $display("FAIL physical plus PC unison");$finish;end
  select_range(2);
  if(held(0,60,0)!=1 || dut.u_core.monitor_key_down!==0)begin $display("FAIL old note retuned/highlighted");$finish;end
  keys[4]=0;wait_frames(8);press_board(1);keys[7]=0;wait_frames(8);
  if(held(4,76,0)!=1 || held(7,79,1)!=1 || held(0,60,0)!=1)
   begin $display("FAIL independent mode/range snapshots");$finish;end
  select_range(0);keys[0]=1;wait_frames(8);
  if(held_count(0)!=3 || held(0,60,0)!=0)begin $display("FAIL cross-range release ownership");$finish;end
  send("PANIC\n");wait_frames(8);
  if(held_count(0)!=2)begin $display("FAIL PC panic cleared physical notes");$finish;end
  keys=13'h1fff;wait_frames(4300);
  if(dut.u_core.voice_count!=0 || pa!==1)begin $display("FAIL old-range tail drain");$finish;end
  // The same accepted edge as KEY1 uses the new range, even under mixed preset selection.
  select_range(1);bk[0]=0;keys[0]=0;wait_frames(8);bk[0]=1;wait_frames(3);
  if(dut.u_core.monitor_octave!=2 || held(0,72,1)!=1)begin $display("FAIL simultaneous octave/note");$finish;end
  keys=0;wait_frames(20);
  send("NOTE_ON 48 100 0\n");send("NOTE_ON 49 100 0\n");send("NOTE_ON 50 100 0\n");wait_frames(12);
  if(dut.u_core.voice_count!=16 || held_count(0)!=16)begin $display("FAIL full16 high range plus PC");$finish;end
  select_range(0);keys=13'h1fff;wait_frames(12);
  if(held_count(0)!=3)begin $display("FAIL full13 release after octave switch");$finish;end
  send("PANIC\n");wait_frames(4300);
  if(dut.u_core.voice_count!=0 || pa!==1)begin $display("FAIL full16 drain");$finish;end
  @(negedge clk);rst=0;bits=0;word=0;repeat(8)@(negedge clk);rst=1;wait_frames(8);
  if(dut.u_core.monitor_octave!=1 || dut.u_core.selected_guitar || held_count(0)!=0)
   begin $display("FAIL octave reset recovery");$finish;end
  if(tested!=78 || nonzero<1000 || words<15000)begin $display("FAIL insufficient coverage");$finish;end
  $display("PASS tb_performance_octaves: 78 notes/two instruments, bounce/hold/wrap/simultaneous press, old-note release, independent PC, full16, real ADC, R924, %0d exact DAC words",words);$finish;
 end
 initial begin #400000000;$display("FAIL octave timeout");$finish;end
endmodule
