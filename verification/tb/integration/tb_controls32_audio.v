`timescale 1ns/1ps
// Six decoded USB contacts share the real allocator/modal/effects/DAC pipeline
// with thirteen physical keys, PC UART and BLE. USB wire transport is tested separately.
module tb_controls32_audio;
 reg [2:0] fn=7;reg ctrl=0;reg [3:0] ck=0;reg [1:0] cval=0;wire cready,sus;wire [74:0] guide;
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
  .ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),.ENHANCED_BRIGHTNESS(1),.ENABLE_CONTROL_FEATURES(1),.GUIDE_MS_CYCLES(1),.ENABLE_CHORUS(1),.ENABLE_DELAY(1),.ENABLE_REVERB(1),
  .ENABLE_BLE(1),.ENABLE_TOUCH(1),.UART_CLKS_PER_BIT(16),.BLE_CLKS_PER_BIT(16),.WATCHDOG_CYCLES(2000000)) dut(
  .function_key_n(fn),.touch_control_valid(ctrl),.touch_control_ready(cready),.touch_control_kind(ck),.touch_control_value(cval),.monitor_sustain(sus),.monitor_guide(guide),
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
    if(cycle-issued!=958)begin $display("FAIL touch changed R958");$finish;end
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
 task command;input [3:0] kind;input [1:0] value;
  begin @(negedge clk);ck=kind;cval=value;ctrl=1;@(posedge clk);while(!cready)@(posedge clk);@(negedge clk);ctrl=0;end
 endtask
 task function_press;input integer index;
  begin fn[index]=0;repeat(30)@(negedge clk);fn[index]=1;repeat(30)@(negedge clk);end
 endtask
 function integer gates;input [8:0] mask,value;integer i;
  begin gates=0;for(i=0;i<32;i=i+1)if(dut.voice_gate[i] && (dut.voice_source_flat[i*9+:9]&mask)==value)gates=gates+1;end
 endfunction
 initial begin
  repeat(8)@(negedge clk);rst=1;wait(core_ready);frames(4);
  function_press(0);if(!sus)begin $display("FAIL sustain key not connected");$finish;end
  keys[0]=0;keys[4]=0;frames(4);keys[0]=1;frames(4);
  if(held(0,0)!=1 || gates(0,0)!=2)begin $display("FAIL sustain release gate");$finish;end
  command(3,1);frames(4);
  if(sus || gates(0,0)!=1 || matching(0,60,0)!=0 || matching(4,64,0)!=1)begin $display("FAIL sustain off killed held note");$finish;end
  command(1,1);command(2,2);frames(2);
  if(!mode || octave!=2 || matching(4,64,0)!=1)begin $display("FAIL screen mode/octave or held identity");$finish;end
  keys[7]=0;frames(4);if(matching(7,79,1)!=1)begin $display("FAIL new note control snapshot");$finish;end
  function_press(0);send("HELLO\n",0);note_on(70,0);frames(3);send("NOTE_OFF 70 0\n",0);frames(3);
  if(gates(9'h180,9'h100)!=1)begin $display("FAIL PC sustain");$finish;end
  ble_state=1;repeat(100)@(negedge clk);send("HELLO\n",1);note_on(71,1);frames(3);send("NOTE_OFF 71 0\n",1);frames(3);
  if(gates(9'h180,9'h180)!=1)begin $display("FAIL BLE sustain");$finish;end
  send("PANIC\n",1);frames(4);
  if(gates(9'h180,9'h180)!=0 || gates(9'h180,9'h100)!=1 || gates(9'h1f0,0)!=2)begin $display("FAIL cancel under sustain isolation");$finish;end
  function_press(2);repeat(5000)@(negedge clk);
  if(guide[57:55]!=2 || guide[36:0]==0)begin $display("FAIL K8 guide start/count-in");$finish;end
  function_press(1);if(!guide[62] || guide[57:55]!=2)begin $display("FAIL K7 missing song interrupted guide");$finish;end
  command(4,0);if(guide[57:55]!=3)begin $display("FAIL touch pause");$finish;end
  function_press(2);if(guide[57:55]!=0 || guide[36:0]!=0)begin $display("FAIL K8 paused reset");$finish;end
  frames(10);if(nonzero<10 || gates(9'h1f0,0)!=2)begin $display("FAIL guide changed audio");$finish;end
  command(3,1);send("PANIC\n",0);keys=13'h1fff;frames(10);
  if(held(0,0)!=0 || gates(0,0)!=0)begin $display("FAIL release after controls");$finish;end
  $display("PASS tb_controls32_audio: real32/R958/three effects; physical+remote sustain, cancellation isolation, screen mode/octave, guide key/touch behavior samples=%0d",samples);$finish;
 end
 initial begin #30000000;$display("FAIL controls32 timeout");$finish;end
endmodule
