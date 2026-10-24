`timescale 1ns/1ps
// Six decoded USB contacts share the real allocator/modal/effects/DAC pipeline
// with thirteen physical keys, PC UART and BLE. USB wire transport is tested separately.
module tb_touch32_audio;
 reg clk=0,rst=0,connected=0,rv=0,pc=1,ble=1,ble_state=0;
 reg [415:0] packet=0;
 reg [12:0] keys=13'h1fff;
 reg [1:0] board=3;
 always #10 clk=~clk;
 wire rr,fv,fr,bad,ev,er,eon,eg,cv,cr,core_ready,mode;
 wire [5:0] active;wire [47:0] ids;wire [71:0] xs,ys;
 wire [7:0] source;wire [6:0] note,velocity;wire [1:0] octave;
 touch_report_decode decode(.clk(clk),.rst_n(core_ready),.connected(connected),.report_valid(rv),.report_ready(rr),
  .report_data(packet),.frame_valid(fv),.frame_ready(fr),.contact_active(active),.contact_id(ids),
  .contact_x(xs),.contact_y(ys),.stream_error(bad));
 touch_contact_tracker #(.CONTACTS(6)) tracker(.clk(clk),.rst_n(core_ready),.connected(connected),.stream_error(bad),
  .frame_valid(fv),.frame_ready(fr),.contact_active(active),.contact_id(ids),.contact_x(xs),.contact_y(ys),
  .instrument_guitar(mode),.octave(octave),.event_valid(ev),.event_ready(er),.event_on(eon),.event_source(source),
  .event_note(note),.event_velocity(velocity),.event_guitar(eg),.control_valid(),.control_ready(1'b1),
  .control_kind(),.control_value(),.cancel_valid(cv),.cancel_ready(cr),.cancel_mask(),.cancel_value(),.fault());
 instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
  .VOICES(32),.FIXED_PIANO(1),.EXTERNAL_PIANO_KEYS(1),.ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),
  .ENABLE_OCTAVE_KEY(1),.USE_MODAL(1),.REQUEST_LEAD_HALF_EDGES(60),
  .ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),.ENABLE_CHORUS(1),.ENABLE_DELAY(1),.ENABLE_REVERB(1),
  .ENABLE_BLE(1),.ENABLE_TOUCH(1),.UART_CLKS_PER_BIT(16),.BLE_CLKS_PER_BIT(16),.WATCHDOG_CYCLES(2000000)) dut(
  .sys_clk(clk),.sys_rst_n(rst),.Key_in(board),.piano_key_n(keys),.uart_rx(pc),.ble_rx(ble),.ble_state(ble_state),
  .knob_value_flat({7'd64,7'd32}),.knob_valid(1'b1),.param_ready(1'b1),.param_fault(1'b0),
  .control_sustain(1'b0),.control_octave(2'd1),.control_brightness(7'd127),.control_ready(core_ready),
  .monitor_instrument_guitar(mode),.monitor_octave(octave),
  .touch_event_valid(ev),.touch_event_ready(er),.touch_event_on(eon),.touch_event_guitar(eg),
  .touch_event_source(source),.touch_event_note(note),.touch_event_velocity(velocity),
  .touch_cancel_valid(cv),.touch_cancel_ready(cr));
 integer cycle=0,issued=0,samples=0,nonzero=0,since_reset=0,n;
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!core_ready)since_reset=0;
  else begin
   if(dut.sample_request)begin issued=cycle;since_reset=since_reset+1;end
   if(dut.output_sample_valid)begin
    if(cycle-issued!=955)begin $display("FAIL touch changed R955");$finish;end
    samples=samples+1;if(dut.output_sample_data!=0)nonzero=nonzero+1;
   end
   if(since_reset>4 && (dut.sample_underrun || dut.g_modal.core_overrun))begin $display("FAIL touch audio underrun");$finish;end
  end
 end
 function integer held;
  input [8:0] mask,value;integer i;
  begin held=0;for(i=0;i<32;i=i+1)if(dut.voice_key_down[i] && (dut.voice_source_flat[i*9+:9]&mask)==value)held=held+1;end
 endfunction
 function integer matching;
  input [8:0] owner;input [6:0] pitch;input guitar;integer i;
  begin matching=0;for(i=0;i<32;i=i+1)if(dut.voice_key_down[i] && dut.voice_source_flat[i*9+:9]==owner &&
   dut.voice_note_flat[i*7+:7]==pitch && dut.voice_timbre_flat[i*4]==guitar)matching=matching+1;end
 endfunction
 task frames;input integer count;integer before_count;
  begin before_count=samples;wait(samples>=before_count+count);@(negedge clk);end
 endtask
 task touch;
  input down;input integer y,first_x;integer i,x;
  begin
   while(!rr)@(negedge clk);packet=0;packet[7:0]=1;packet[415:408]=6;
   for(i=0;i<6;i=i+1)begin
    case(i)0:x=first_x;1:x=200;2:x=330;3:x=450;4:x=600;default:x=730;endcase
    packet[8+i*64]=down;packet[16+i*64+:8]=10+i;
    packet[24+i*64+:16]=x*4;packet[40+i*64+:16]=(y*4096+599)/600;
   end
   rv=1;@(negedge clk);rv=0;frames(4);
  end
 endtask
 task send;
  input [511:0] message;input to_ble;integer length,i,j,k;reg bit_value;
  begin
   length=0;for(k=0;k<64;k=k+1)if(message[k*8+:8]!=0)length=k+1;
   for(i=length-1;i>=0;i=i-1)begin
    @(negedge clk);if(to_ble)ble=0;else pc=0;repeat(16)@(negedge clk);
    for(j=0;j<8;j=j+1)begin bit_value=message[i*8+j];if(to_ble)ble=bit_value;else pc=bit_value;repeat(16)@(negedge clk);end
    if(to_ble)ble=1;else pc=1;repeat(16)@(negedge clk);
   end
   repeat(100)@(negedge clk);
  end
 endtask
 task note_on;
  input integer pitch;input to_ble;reg [7:0] tens,ones;
  begin tens=48+pitch/10;ones=48+pitch%10;send({"NOTE_ON ",tens,ones," 100 0\n"},to_ble);end
 endtask
 task board_press;input integer index;
  begin board[index]=0;repeat(100)@(negedge clk);board[index]=1;repeat(100)@(negedge clk);end
 endtask
 initial begin
  repeat(8)@(negedge clk);rst=1;wait(core_ready);frames(4);
  connected=1;touch(1,500,70);
  if(held(9'h1f0,9'h040)!=6 || matching(9'h040,60,0)!=1)begin $display("FAIL six touch notes");$finish;end
  keys=0;frames(4);send("HELLO\n",0);for(n=73;n<=85;n=n+1)note_on(n,0);frames(32);
  if(dut.voice_count!=32 || held(0,0)!=32 || dut.steal_count!=0)begin $display("FAIL touch/physical/PC full32");$finish;end
  ble_state=1;repeat(100)@(negedge clk);send("HELLO\n",1);note_on(86,1);frames(4);
  if(held(0,0)!=32 || dut.steal_count!=1 || held(9'h180,9'h180)!=1)begin $display("FAIL BLE 33rd voice");$finish;end
  connected=0;frames(4);
  if(held(9'h1f0,9'h040)!=0 || held(9'h1f0,0)!=13 || held(9'h180,9'h100)!=13 || held(9'h180,9'h180)!=1)begin
   $display("FAIL USB disconnect cleared other source");$finish;
  end
  send("PANIC\n",1);frames(4);
  if(held(9'h180,9'h180)!=0 || held(9'h180,9'h100)!=13 || held(9'h1f0,0)!=13)begin $display("FAIL BLE cancel isolation");$finish;end
  send("PANIC\n",0);frames(4);
  if(held(0,0)!=13)begin $display("FAIL PC cancel isolation");$finish;end
  keys=13'h1fff;frames(4);if(held(0,0)!=0)begin $display("FAIL physical release");$finish;end
  connected=1;touch(1,500,70);board_press(1);touch(1,500,70);
  if(matching(9'h040,60,0)!=1)begin $display("FAIL held touch timbre changed");$finish;end
  touch(0,500,70);board_press(0);touch(1,550,70);
  if(matching(9'h040,72,1)!=1 || held(9'h1f0,9'h040)!=6)begin $display("FAIL new octave/guitar touch");$finish;end
  touch(1,550,200);
  if(matching(9'h040,74,1)!=1 || matching(9'h040,72,1)!=0 || held(0,0)!=6)begin $display("FAIL touch slide");$finish;end
  touch(0,550,200);if(held(0,0)!=0 || nonzero<10)begin $display("FAIL touch release/audio");$finish;end
  rst=0;repeat(8)@(negedge clk);if(dut.voice_key_down!=0)begin $display("FAIL dirty reset");$finish;end
  $display("PASS tb_touch32_audio: six contacts+13 physical+13 PC full32, BLE 33rd steal, per-source cancels, slide/timbre/octave/reconnect/reset, nonzero audio R955 samples=%0d",samples);$finish;
 end
 initial begin #30000000;$display("FAIL touch32 integration timeout");$finish;end
endmodule
