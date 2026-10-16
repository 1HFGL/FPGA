`timescale 1ns/1ps
// Repeated mixed-source performance and recovery on the actual 16-voice core.
// UART is accelerated; the 50MHz/48kHz engine and release envelopes are real.
module tb_music_recovery;
 reg clk=0,rst=0,rx=1;reg [1:0] keys=3;
 integer cycle=0,request_at=0,frames=0,checks=0,rounds,j,n;
 reg [8191:0] command;
 always #10 clk=~clk;
 music_performance_core #(.DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16),.WATCHDOG_CYCLES(500000)) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(keys),.uart_rx(rx),.uart_tx(),
  .HP_BCK(),.HP_WS(),.HP_DIN(),.PA_EN(),
  .external_control_valid(1'b0),.external_control_ready(),.external_volume(7'd8),.external_bend(11'd512),
  .monitor_volume(),.monitor_bend(),.monitor_keys(),.monitor_guitar(),.monitor_valid(),.monitor_sample());
 always @(posedge clk)begin
  cycle=cycle+1;
  if(dut.audio_ready)begin
   if(dut.sample_request)begin request_at=cycle;frames=frames+1;end
   if(dut.sample_valid)begin
    checks=checks+1;
    if(cycle-request_at!=924 || dut.overrun!==0 || dut.sample_clipped!==0 ||
       (^dut.sample_data)===1'bx || dut.voice_count>16)begin
     $display("FAIL recovery: deadline/overrun/clipping/unknown/count");$finish;
    end
   end
  end
 end
 function integer text_length;input [8191:0] text;integer k;
 begin text_length=0;for(k=0;k<1024;k=k+1)if(text[k*8+:8]!=0)text_length=k+1;end endfunction
 task send;input [8191:0] text;integer a,b;
 begin
  for(a=0;a<text_length(text);a=a+1)begin
   @(negedge clk);rx=0;repeat(16)@(negedge clk);
   for(b=0;b<8;b=b+1)begin rx=(text[(text_length(text)-1-a)*8+:8]>>b)&1;repeat(16)@(negedge clk);end
   rx=1;repeat(16)@(negedge clk);
  end
  repeat(20)@(negedge clk);
 end endtask
 task wait_frames;input integer count;integer start;
 begin start=frames;wait(frames>=start+count);@(negedge clk);end endtask
 task check_held;input integer pc,physical;integer k,p,h;
 begin
  p=0;h=0;
  for(k=0;k<16;k=k+1)if(dut.voice_gate[k])begin
   if(dut.voice_source_flat[k*8+7])p=p+1;else h=h+1;
  end
  if(p!=pc || h!=physical)begin $display("FAIL recovery owners round=%0d PC=%0d local=%0d",rounds,p,h);$finish;end
 end endtask
 initial begin
  repeat(8)@(negedge clk);rst=1;wait(dut.audio_ready);wait_frames(4);
  if(dut.target_volume!==8 || dut.global_gain_q16!==4096 || dut.target_bend!==512)begin
   $display("FAIL recovery boot volume");$finish;end
  keys=2;wait_frames(4);send("HELLO\n");repeat(20000)@(negedge clk);
  check_held(0,1);
  for(rounds=0;rounds<64;rounds=rounds+1)begin
   $sformat(command,"PRESET %0d\n",rounds%2);send(command);repeat(20000)@(negedge clk);
   if(rounds%3==0)send("CONTROL 0 0\n");
   else if(rounds%3==1)send("CONTROL 127 1024\n");
   else send("CONTROL 8 512\n");
   repeat(20000)@(negedge clk);
   for(j=0;j<4;j=j+1)begin
    n=60+j*4;$sformat(command,"NOTE_ON %0d 100 0\n",n);send(command);
   end
   wait_frames(2);check_held(4,1);
   // Retrigger within the same held chord must reuse the PC owner.
   send("NOTE_ON 60 1 0\n");wait_frames(2);check_held(4,1);
   case(rounds%4)
    0:begin
     for(j=0;j<4;j=j+1)begin $sformat(command,"NOTE_OFF %0d 0\n",60+j*4);send(command);end
    end
    1:send("PANIC\n");
    2:begin send("HELLO\n");repeat(20000)@(negedge clk);end
    3:begin
     repeat(500100)@(negedge clk);
     if(dut.session_ready)begin $display("FAIL recovery watchdog");$finish;end
     check_held(0,1);send("HELLO\n");repeat(20000)@(negedge clk);
    end
   endcase
   wait_frames(2);check_held(0,1);
   if(dut.steal_count!==0)begin $display("FAIL recovery leaked owners");$finish;end
  end
  keys=3;wait_frames(4300);
  if(dut.voice_count!==0 || dut.sample_data!==0)begin $display("FAIL recovery stuck tails");$finish;end
  // Reset at high gain, with both an active bank and an unfinished UART line.
  send("HELLO\n");repeat(20000)@(negedge clk);send("CONTROL 127 0\n");wait_frames(140);
  keys=2;wait_frames(5);send("NOTE_ON 72 ");
  wait(dut.u_bank.busy);@(negedge clk);rst=0;rx=1;repeat(8)@(negedge clk);
  if(dut.target_volume!==8 || dut.global_gain_q16!==4096 || dut.target_bend!==512)begin
   $display("FAIL recovery reset volume");$finish;end
  rst=1;wait(dut.audio_ready);wait_frames(6);check_held(0,1);
  if(dut.session_ready || dut.global_gain_q16!==4096)begin $display("FAIL recovery stale session/gain");$finish;end
  send("100 0\n");wait_frames(4);check_held(0,1);
  send("HELLO\n");repeat(20000)@(negedge clk);send("NOTE_ON 72 100 0\n");wait_frames(4);check_held(1,1);
  send("PANIC\n");keys=3;wait_frames(4300);
  if(dut.voice_count!==0 || dut.sample_data!==0 || checks<18000)begin $display("FAIL recovery final cleanup/coverage %0d",checks);$finish;end
  $display("PASS tb_music_recovery: 64 repeated chords/retriggers, preset/control changes, PC/local isolation, 16 watchdog recoveries, busy/partial-line reset, %0d R924 samples",checks);$finish;
 end
 initial begin #1000000000;$display("FAIL recovery timeout");$finish;end
endmodule
