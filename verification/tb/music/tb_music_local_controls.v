`timescale 1ns/1ps
// Future C synchronous control interface, exercised on the actual shared system.
module tb_music_local_controls;
 reg clk=0,rst=0,rx=1,local_valid=0;
 reg [6:0] local_volume=127;reg [10:0] local_bend=512;
 wire ready,tx,bv,be;wire [7:0] bd;
 wire [6:0] volume;wire signed [15:0] bend;
 reg [8191:0] line=0,replies[0:31];integer nr=0,next_reply=0;
 integer frames=0,start_frame;
 always #10 clk=~clk;
 music_performance_core #(.DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16),.WATCHDOG_CYCLES(500000)) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(2'b11),.uart_rx(rx),.uart_tx(tx),
  .HP_BCK(),.HP_WS(),.HP_DIN(),.PA_EN(),
  .external_control_valid(local_valid),.external_control_ready(ready),
  .external_volume(local_volume),.external_bend(local_bend),
  .monitor_volume(volume),.monitor_bend(bend),.monitor_keys(),
  .monitor_guitar(),.monitor_valid(),.monitor_sample());
 uart_rx #(.CLKS_PER_BIT(16)) monitor(.clk(clk),.rst_n(rst),.rx(tx),.valid(bv),.data(bd),.frame_error(be));
 always @(posedge clk)begin
  if(dut.sample_request && dut.audio_ready)frames=frames+1;
  if(be)begin $display("FAIL local reply framing");$finish;end
  if(bv)begin
   if(bd==10)begin
    if(nr>=32)begin $display("FAIL reply capacity");$finish;end
    replies[nr]=line;nr=nr+1;line=0;
   end else line={line,bd};
  end
 end
 function integer text_length;input [8191:0] text;integer j;
 begin text_length=0;for(j=0;j<1024;j=j+1)if(text[j*8+:8]!=0)text_length=j+1;end endfunction
 task send;input [8191:0] text;integer a,b;
 begin
  for(a=0;a<text_length(text);a=a+1)begin
   @(negedge clk);rx=0;repeat(16)@(negedge clk);
   for(b=0;b<8;b=b+1)begin rx=(text[(text_length(text)-1-a)*8+:8]>>b)&1;repeat(16)@(negedge clk);end
   rx=1;repeat(16)@(negedge clk);
  end
  repeat(8)@(negedge clk);
 end endtask
 task expect_line;input [8191:0] wanted;
 begin
  wait(nr>next_reply);@(negedge clk);
  if(replies[next_reply]!==wanted)begin $display("FAIL local reply: %s",replies[next_reply]);$finish;end
  next_reply=next_reply+1;
 end endtask
 task set_local;input [6:0] v;input [10:0] b;
 begin
  @(negedge clk);local_volume=v;local_bend=b;local_valid=1;
  @(negedge clk);local_valid=0;
 end endtask
 task check_target;input [6:0] v;input [10:0] b;input signed [15:0] display_bend;
 begin
  if(volume!==v || dut.target_bend!==b || bend!==display_bend)begin
   $display("FAIL local target/display v=%0d b=%0d display=%0d",volume,dut.target_bend,bend);$finish;
  end
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;wait(dut.audio_ready);repeat(5)@(negedge clk);
  if(!ready)begin $display("FAIL local ready");$finish;end
  check_target(8,512,0);
  // A C producer can work before a PC HELLO. No serial session is needed.
  set_local(64,0);check_target(64,0,-16'sd32768);
  start_frame=frames;wait(frames>=start_frame+130);@(negedge clk);
  if(dut.global_gain_q16!==32768 || dut.bend_current!==0 || dut.pitch_ratio_q16!==58386)begin
   $display("FAIL local settling");$finish;end
  @(negedge clk);local_volume=0;local_bend=2047;local_valid=1;#1;
  if(ready)begin $display("FAIL invalid local ready");$finish;end
  repeat(10)@(negedge clk);check_target(64,0,-16'sd32768);local_valid=0;local_bend=512;
  send("HELLO\n");expect_line("SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=16 SAMPLE_RATE=48000 FW=music-classic16 TONE=PIANO_ROCK");
  check_target(64,0,-16'sd32768);
  send("NOTE_ON 60 100 0\n");repeat(1500)@(negedge clk);
  if(dut.voice_count!==1 || dut.voice_gate!==16'h0001)begin $display("FAIL local test note");$finish;end
  // Hold the valid local pair across the UART acceptance edge: local wins,
  // UART is explicitly rejected and the PC note must not be cancelled.
  local_volume=33;local_bend=800;local_valid=1;
  send("CONTROL 0 0\n");expect_line("ERROR 0 BUSY");local_valid=0;
  check_target(33,800,16'sd18432);
  if(dut.voice_gate!==16'h0001)begin $display("FAIL control contention cancelled note");$finish;end
  send("CONTROL 100 1024\n");
  expect_line("STATUS VOICE_COUNT=1 MAX_VOICE_COUNT=1 STEAL_COUNT=0 SAMPLE_RATE=48000 PRESET=1 VOLUME=100 BEND=1024");
  check_target(100,1024,16'sd32767);
  send("PANIC\n");repeat(1500)@(negedge clk);check_target(100,1024,16'sd32767);
  if(dut.voice_gate!==0)begin $display("FAIL panic release");$finish;end
  repeat(500100)@(negedge clk);check_target(100,1024,16'sd32767);
  if(dut.session_ready)begin $display("FAIL local watchdog");$finish;end
  // C remains usable while the serial session has expired.
  set_local(127,512);check_target(127,512,0);
  set_local(5,333);check_target(5,333,-16'sd11456);
  rst=0;repeat(10)@(negedge clk);check_target(8,512,0);
  if(ready)begin $display("FAIL ready during reset");$finish;end
  rst=1;wait(dut.audio_ready);repeat(5)@(negedge clk);check_target(8,512,0);
  $display("PASS tb_music_local_controls: C/UART priority, atomic rejection, display mapping, PC isolation, reset");$finish;
 end
 initial begin #30000000;$display("FAIL local control timeout");$finish;end
endmodule
