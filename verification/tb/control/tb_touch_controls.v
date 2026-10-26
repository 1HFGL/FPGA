`timescale 1ns/1ps
// 六触点与新增控件共报告；背压撤销及滑奏不得误触控制。
module tb_touch_controls;
 reg clk=0,rst=0,connected=1,error=0,fv=0,ready=1;
 reg [5:0] active=0;reg [47:0] ids=0;reg [71:0] xs=0,ys=0;
 wire fr,cv,ev,on,cancel;wire [3:0] kind;wire [1:0] value;
 integer count=0,notes=0,i,before_count;reg [3:0] expected_kind=4;
 always #10 clk=~clk;
 touch_contact_tracker #(.CONTACTS(6),.CONTROL_WIDTH(4),.EXTENDED_CONTROLS(1)) dut(
 .clk(clk),.rst_n(rst),.connected(connected),.stream_error(error),.frame_valid(fv),.frame_ready(fr),
 .contact_active(active),.contact_id(ids),.contact_x(xs),.contact_y(ys),.instrument_guitar(1'b0),.octave(2'd1),
 .event_valid(ev),.event_ready(1'b1),.event_on(on),.event_source(),.event_note(),.event_velocity(),.event_guitar(),
 .control_valid(cv),.control_ready(ready),.control_kind(kind),.control_value(value),
 .cancel_valid(cancel),.cancel_ready(1'b1),.cancel_mask(),.cancel_value(),.fault());
 always @(posedge clk)if(rst)begin
  if(cv && ready)begin if(kind!=expected_kind)begin $display("FAIL control kind %d",kind);$finish;end count=count+1;end
  if(ev && on)notes=notes+1;
 end
 task point;input integer n,x,y;
  begin active[n]=1;ids[n*8+:8]=n+1;xs[n*12+:12]=x;ys[n*12+:12]=y;end
 endtask
 task send_frame;
  begin @(negedge clk);while(!fr)@(negedge clk);fv=1;@(negedge clk);fv=0;end
 endtask
 task finish_frame;
  begin while(!fr)@(negedge clk);repeat(30)@(negedge clk);end
 endtask
 task release_all;
  begin active=0;send_frame;finish_frame;end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(i=0;i<5;i=i+1)point(i,80+i*110,520);
  point(5,900,270);send_frame;finish_frame;
  if(notes!=5 || count!=1)begin $display("FAIL shared note/control report");$finish;end
  send_frame;finish_frame;if(count!=1 || notes!=5)begin $display("FAIL held repeated");$finish;end
  release_all;
  point(0,80,520);send_frame;finish_frame;
  point(0,900,270);send_frame;finish_frame;
  if(count!=1)begin $display("FAIL glissando fired control");$finish;end release_all;
  // 新触点控件受背压时内容稳定，断连后即使ready恢复也不执行。
  ready=0;point(0,900,270);send_frame;wait(cv);repeat(20)@(negedge clk);
  if(!cv || kind!=4)begin $display("FAIL stalled control");$finish;end
  connected=0;ready=1;repeat(70)@(negedge clk);
  if(count!=1 || cv)begin $display("FAIL stale disconnect command");$finish;end
  connected=1;release_all;
  ready=0;point(0,900,270);send_frame;wait(cv);@(negedge clk);error=1;ready=1;
  @(negedge clk);error=0;repeat(70)@(negedge clk);
  if(count!=1)begin $display("FAIL stale corrupt report command");$finish;end release_all;
  expected_kind=7;point(0,200,180);send_frame;finish_frame;release_all;
  expected_kind=5;point(0,900,320);send_frame;finish_frame;release_all;
  expected_kind=9;point(0,630,180);send_frame;finish_frame;release_all;
  point(0,680,180);send_frame;finish_frame;release_all;
  if(count!=5)begin $display("FAIL extended controls missing");$finish;end
  $display("PASS tb_touch_controls: six contacts, held/glissando, backpressure, disconnect/error cancellation, guide/song/tempo controls");$finish;
 end
 initial begin #3000000;$display("FAIL touch controls timeout");$finish;end
endmodule
