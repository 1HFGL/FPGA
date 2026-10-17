`timescale 1ns/1ps
// Default release and real 115200 baud. No shortened audio envelope.
module tb_music_uart16;
 reg clk=0,rst=0,rx=1;reg [1:0] keys=3;
 wire tx,bck,ws,din,pa;wire [7:0] reply_byte;wire reply_valid,reply_bad;
 integer cycle=0,frames=0,words=0,bits=0,request_at=0,total=0,nonzero=0,v,i;
 reg [15:0] previous=0,received=0,expected[0:65535];
 integer energy[0:15];reg [8191:0] reply=0,command;reg hello_seen=0,status_seen=0,unsupported_seen=0;
 always #10 clk=~clk;
 music_uart_top #(.VOICES(16),.DEBOUNCE_CYCLES(8),.WATCHDOG_CYCLES(6000000)) dut(
 .sys_clk(clk),.sys_rst_n(rst),.Key_in(keys),.uart_rx(rx),.uart_tx(tx),
 .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
 uart_rx monitor(.clk(clk),.rst_n(rst),.rx(tx),.data(reply_byte),.valid(reply_valid),.frame_error(reply_bad));
 always @(posedge clk)begin
  cycle=cycle+1;
  if(reply_bad)begin $display("FAIL: bad TX framing"); $finish; end
  if(reply_valid)begin
   if(reply_byte==10)begin
    if(reply=="SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=16 SAMPLE_RATE=48000 FW=music-classic16 TONE=PIANO_ROCK")hello_seen=1;
    else if(reply=="STATUS VOICE_COUNT=16 MAX_VOICE_COUNT=16 STEAL_COUNT=0 SAMPLE_RATE=48000 PRESET=0 VOLUME=8 BEND=512")status_seen=1;
    else if(reply=="ERROR 7 UNSUPPORTED")unsupported_seen=1;
    else if(text_length(reply)>=7 && (reply >> ((text_length(reply)-7)*8))=="STATUS ")begin end
    else if(reply!="ERROR 0 NOT_READY")begin $display("FAIL: unexpected reply %s",reply); $finish; end
    reply=0;
   end else reply={reply,reply_byte};
  end
  if(!dut.u_core.audio_ready)begin frames=0;previous=0;request_at=0;end
  else begin
   if(dut.u_core.sample_request)request_at=cycle;
   if(dut.u_core.u_b.frame_start)begin
    if(frames>=65536)begin $display("FAIL: capture overflow"); $finish; end expected[frames]=previous;frames=frames+1;
   end
   if(dut.u_core.sample_valid)begin
    if(cycle-request_at!=924 || dut.u_core.sample_clipped!==0 || dut.u_core.overrun!==0)begin $display("FAIL: deadline/clipping/overrun"); $finish; end
    previous=dut.u_core.sample_data;
    if(dut.u_core.voice_gate==16'hffff)for(v=0;v<16;v=v+1)begin
     energy[v]=energy[v]+(dut.u_core.u_bank.last_voice[v]<0 ? -dut.u_core.u_bank.last_voice[v]:dut.u_core.u_bank.last_voice[v]);
    end
   end
  end
 end
 always @(posedge bck or negedge rst)begin
  if(!rst)begin bits=0;words=0;received=0;end
  else if(dut.u_core.audio_ready)begin
   if(ws!==(words%2) || dut.u_core.sample_underrun!==(words<2))begin $display("FAIL: channel/underrun"); $finish; end
   received={received[14:0],din};bits=bits+1;
   if(bits==16)begin
`ifdef NEGATIVE_CONTROL
    if(words==0)received=received^1;
`endif
    if(received!==expected[words/2])begin $display("FAIL: serial mismatch word=%0d",words); $finish; end
    if(received!=0)nonzero=nonzero+1;
    words=words+1;total=total+1;bits=0;
   end
  end
 end
 task send(input [8191:0] text);
 integer a,b;
 begin
  for(a=0;a<text_length(text);a=a+1)begin
   @(negedge clk);rx=0;repeat(434)@(negedge clk);
   for(b=0;b<8;b=b+1)begin rx=(text[(text_length(text)-1-a)*8+:8]>>b)&1;repeat(434)@(negedge clk);end
   rx=1;repeat(434)@(negedge clk);
  end
  repeat(80)@(negedge clk);
 end endtask
 task wait_frames(input integer n);
 integer start;
 begin start=frames;wait(frames>=start+n);@(negedge clk);end endtask
 function integer held_pc; input unused;
 integer j;begin held_pc=0;for(j=0;j<16;j=j+1)if(dut.u_core.voice_gate[j] && dut.u_core.voice_source_flat[j*8+7])held_pc=held_pc+1;end endfunction
 initial begin
  for(i=0;i<16;i=i+1)energy[i]=0;
  repeat(5)@(negedge clk);rst=1;wait_frames(5);
  send("HELLO\n");wait(hello_seen);@(negedge clk);
  send("PRESET 0\n");if(dut.u_core.selected_preset!==0)begin $display("FAIL: rock selection"); $finish; end
  for(i=0;i<16;i=i+1)begin $sformat(command,"NOTE_ON %0d 1 0\n",48+i*2);send(command);end
  wait_frames(250);
  if(dut.u_core.voice_count!=16 || held_pc(1'b0)!=16 || dut.u_core.max_voice_count!=16)begin $display("FAIL: sixteen voices"); $finish; end
  for(i=0;i<16;i=i+1)if(energy[i]==0 || dut.u_core.voice_velocity_flat[i*7+:7]!=100)begin $display("FAIL: silent slot/fixed velocity %0d",i); $finish; end
  send("STATUS?\n");wait(status_seen);@(negedge clk);
  if(dut.u_core.u_bank.instrument_active!==16'h0000)begin $display("FAIL: sixteen rock voices"); $finish; end
  send("CONTROL 0 1024\n");wait_frames(140);
  if(dut.u_core.global_gain_q16!==0 || dut.u_core.u_controls.bend_current!==1024 || dut.u_core.sample_data!==0 || held_pc(1'b0)!=16)
   begin $display("FAIL UART mute/bend/voice lifetime");$finish;end
  send("CONTROL 64 0\n");wait_frames(140);
  if(dut.u_core.global_gain_q16!==32768 || dut.u_core.u_controls.bend_current!==0 || held_pc(1'b0)!=16)
   begin $display("FAIL UART unmute/down-bend");$finish;end
  send("CONTROL 127 512\n");wait_frames(140);
  // Preset changes leave all held guitar voices intact; next retrigger changes one.
  send("PRESET 1\n");wait_frames(5);
  if(dut.u_core.u_bank.instrument_active!==16'h0000)begin $display("FAIL: held guitar changed"); $finish; end
  send("APPLY 7\n");wait(unsupported_seen);@(negedge clk);
  send("NOTE_ON 78 127 0\n");if(held_pc(1'b0)!=16 || dut.u_core.steal_count!=0)begin $display("FAIL: same-note retrigger"); $finish; end
  wait_frames(5);
  if(dut.u_core.u_bank.instrument_active!==16'h8000)begin $display("FAIL: retrigger did not choose piano"); $finish; end
  send("NOTE_ON 84 100 0\n");if(held_pc(1'b0)!=16 || dut.u_core.steal_count!=1)begin $display("FAIL: seventeenth steal"); $finish; end
  send("NOTE_OFF 48 0\n");if(held_pc(1'b0)!=16)begin $display("FAIL: stale note-off closed new owner"); $finish; end
  wait_frames(5);
  if(dut.u_core.u_bank.instrument_active!==16'h8001)begin $display("FAIL: stolen slot did not choose piano"); $finish; end
  send("PRESET 0\n");
  send("PANIC\n");wait_frames(5);
  if(dut.u_core.u_bank.instrument_active!==16'h8001)begin $display("FAIL: tails changed preset"); $finish; end
  if(held_pc(1'b0)!=0 || dut.u_core.voice_count!=16)begin $display("FAIL: tail prematurely freed"); $finish; end
  wait_frames(4105);if(dut.u_core.voice_count!=0 || pa!==1)begin $display("FAIL: tail stuck"); $finish; end
  keys=2;wait_frames(50);
  if(dut.u_core.u_bank.instrument_active[0]!==0)begin $display("FAIL: physical key not rock"); $finish; end
  send("PRESET 1\n");wait_frames(5);
  if(dut.u_core.u_bank.instrument_active[0]!==0)begin $display("FAIL: held physical key changed"); $finish; end
  send("NOTE_ON 60 100 0\n");send("NOTE_ON 64 100 0\n");wait_frames(50);
  if(dut.u_core.voice_count!=3 || held_pc(1'b0)!=2)begin $display("FAIL: physical and PC same note merged"); $finish; end
  send("NOTE_OFF 60 0\n");wait_frames(4105);
  if(dut.u_core.voice_count!=2 || held_pc(1'b0)!=1)begin $display("FAIL: PC release damaged physical"); $finish; end
  send("NOTE_ON 60 100 0\n");send("PANIC\n");wait_frames(4105);
  if(dut.u_core.voice_count!=1 || held_pc(1'b0)!=0 || pa!==0)begin $display("FAIL: PANIC scope"); $finish; end
  send("NOTE_ON 67 100 0\n");repeat(6000100)@(negedge clk);wait_frames(4105);
  if(dut.u_core.session_ready || held_pc(1'b0)!=0 || dut.u_core.voice_count!=1)begin $display("FAIL: watchdog scope"); $finish; end
  send("NOTE_ON 72 100 0\n");wait_frames(5);if(dut.u_core.voice_count!=1)begin $display("FAIL: unready accepted note"); $finish; end
  send("HELLO\n");wait_frames(500);send("NOTE_ON 72 100 0\n");wait_frames(20);
  if(dut.u_core.voice_count!=2)begin $display("FAIL: reconnect"); $finish; end
  rst=0;#1;if(tx!==1 || pa!==1)begin $display("FAIL: reset outputs"); $finish; end
  keys=3;repeat(5)@(negedge clk);rst=1;wait_frames(20);
  if(dut.u_core.voice_count!=0 || dut.u_core.session_ready || pa!==1)begin $display("FAIL: reset state"); $finish; end
  if(total<40000 || nonzero<2000)begin $display("FAIL: insufficient serial coverage"); $finish; end
  $display("PASS tb_music_uart16: 16 nonzero rock voices, piano/rock snapshot switching, 17th steal, owners, default tails, watchdog, R924, %0d serial words",total);$finish;
 end
 initial begin #900000000;begin $display("FAIL: UART16 timeout"); $finish; end end
 function integer text_length;
 input [8191:0] text;
 integer q;
 begin text_length=0;for(q=0;q<1024;q=q+1)if(text[q*8+:8]!=0)text_length=q+1;end
 endfunction
endmodule
