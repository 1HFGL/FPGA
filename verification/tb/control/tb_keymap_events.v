`timescale 1ns/1ps
module tb_keymap_events;
 reg clk=0,rst=0,ready=1;reg [12:0] press=0,release_key=0;reg [103:0] map=0;
 wire idle,valid,on,fault;wire [6:0] note;wire [7:0] source;integer i,events=0;
 reg [6:0] enote[0:9];reg [7:0] esource[0:9];reg eon[0:9];integer expected=0;
 always #5 clk=~clk;
 event_encoder #(.KEY_COUNT(13),.SOURCE_WIDTH(8),.CHROMATIC_KEYS(1),.ENABLE_PLAY_CONTROL(1),.ENABLE_KEYMAP(1)) dut(
 .clk(clk),.rst_n(rst),.key_press(press),.key_release(release_key),.key_velocity_flat({13{7'd100}}),
 .input_timbre(4'd0),.octave_select(2'd1),.input_overflow(fault),.event_valid(valid),.event_type(on),
 .event_source_id(source),.event_note(note),.event_velocity(),.event_timbre(),.event_ready(ready),.keymap(map),.mapping_idle(idle));
 always @(posedge clk)if(rst && valid && ready)begin
  if(events>=expected || note!=enote[events] || source!=esource[events] || on!=eon[events])begin
   $display("FAIL keymap event %d source=%d note=%d on=%d",events,source,note,on);$finish;end
  events=events+1;
 end
 task expect_event;input integer src,pitch;input is_on;
 begin esource[expected]=src;enote[expected]=pitch;eon[expected]=is_on;expected=expected+1;end endtask
 task edge_key;input integer key;input down;
 begin @(negedge clk);if(down)press[key]=1;else release_key[key]=1;#1;
  if(idle)begin $display("FAIL map commit allowed same-edge key");$finish;end
  @(negedge clk);press=0;release_key=0;repeat(80)@(negedge clk);end endtask
 initial begin
  for(i=0;i<13;i=i+1)map[i*8+:8]=i;
  repeat(5)@(negedge clk);rst=1;
  expect_event(0,60,1);edge_key(0,1);if(!idle)begin $display("FAIL mapping idle");$finish;end
  map[7:0]=12;expect_event(0,60,0);edge_key(0,0);
  expect_event(0,72,1);edge_key(0,1);map[7:0]=255;expect_event(0,72,0);edge_key(0,0);
  edge_key(0,1);edge_key(0,0);if(events!=4)begin $display("FAIL disabled key event");$finish;end
  map[7:0]=4;map[15:8]=4;
  expect_event(1,64,1);expect_event(0,64,1);
  @(negedge clk);press=3;ready=0;@(negedge clk);press=0;repeat(100)@(negedge clk);
  if(idle || !valid)begin $display("FAIL mapping changed with queued events");$finish;end
  ready=1;repeat(100)@(negedge clk);if(!idle || events!=6)begin $display("FAIL queued sources");$finish;end
  expect_event(0,64,0);edge_key(0,0);expect_event(1,64,0);edge_key(1,0);
  if(fault || events!=8)begin $display("FAIL keymap final");$finish;end
  $display("PASS tb_keymap_events: held release keeps original pitch, disable, duplicate mapping/source identity, queue/same-edge commit exclusion");$finish;
 end
 initial begin #100000;$display("FAIL keymap timeout");$finish;end
endmodule
