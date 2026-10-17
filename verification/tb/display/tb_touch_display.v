`timescale 1ns/1ps
// Full RGB frames from the actual display pipeline, including CDC and font ROM.
module tb_touch_display;
 reg clk=0,pclk=0,rst=0,ready=0,mode=0;
 reg [6:0] brightness=127;
 wire [23:0] rgb;wire de,fs;
 always #10 clk=~clk;
 always #10.204082 pclk=~pclk;
 instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),.TOUCH_PANEL(1),
  .H_FRONT(40),.H_SYNC(104),.H_BACK(144),.V_FRONT(3),.V_SYNC(7),.V_BACK(14),.HS_ACTIVE(0),.VS_ACTIVE(1)) dut(
  .sys_clk(clk),.pixel_clk(pclk),.rst_n(rst),.key_down(13'h91),.piano_keys(13'h91),.guitar_keys(13'h91),
  .volume(7'd32),.pitch_bend(16'd0),.octave(2'd1),.sustain(1'b0),.instrument_guitar(mode),
  .brightness(brightness),.touch_available(ready),.audio_valid(1'b0),.audio_sample(16'd0),
  .lcd_rgb(rgb),.lcd_de(de),.lcd_hsync(),.lcd_vsync(),.frame_start(fs),.display_sample_drop());
 integer frames=0,x=0,y=0,fd[0:2],pixels=0,thumb_checks=0,label_pixels=0,i;
 reg tracking=0;
 reg [73:0] snapshot;
 reg [23:0] expected_color;
 integer center;
 always @(posedge pclk)begin
  #1;
  if(fs)begin
   frames=frames+1;x=0;y=0;tracking=1;snapshot=dut.state_frame;
   if(frames==5)begin
    for(i=0;i<3;i=i+1)$fclose(fd[i]);
    if(pixels!=3*614400 || thumb_checks!=3*1024 || label_pixels<300)begin $display("FAIL touch display coverage %0d %0d %0d",pixels,thumb_checks,label_pixels);$finish;end
    $display("PASS tb_touch_display: three actual RGB frames, %0d independent slider-row pixels, labels, atomic CDC, disconnected/zero/midpoint",thumb_checks);$finish;
   end
  end else if(tracking)begin if(x==1311)begin x=0;y=y+1;end else x=x+1;end
  if(tracking && frames>=2 && frames<=4)begin
   if(y<600 && dut.state_frame!==snapshot)begin $display("FAIL touch display midframe tearing");$finish;end
   if(de)begin
    if((^rgb)===1'bx)begin $display("FAIL touch undefined pixel");$finish;end
    pixels=pixels+1;$fdisplay(fd[frames-2],"%06x",rgb);
    if(y==46)begin
     center=(frames==2)?860:(frames==3)?352:608;
     // At y=46: no labels/track at x336..876, so thumb has an independent exact expectation.
     if(x>=336 && x<876)begin
      expected_color=(frames==4)?24'h211a14:24'h141d24;
      if(x>=center-6 && x<center+6)expected_color=(frames==2)?24'h8ea0ac:(frames==3)?24'h65d9ed:24'hf0b76b;
      if(rgb!==expected_color)begin $display("FAIL touch thumb geometry frame=%0d x=%0d got=%h expected=%h",frames,x,rgb,expected_color);$finish;end
     end
     thumb_checks=thumb_checks+1;
    end
    if(x>=352 && x<430 && y>=12 && y<36 && rgb==24'he8eef2)label_pixels=label_pixels+1;
   end
  end
 end
 initial begin
  fd[0]=$fopen("build/regression/final/touch_disconnected.hex","w");
  fd[1]=$fopen("build/regression/final/touch_dark.hex","w");
  fd[2]=$fopen("build/regression/final/touch_guitar_mid.hex","w");
  #103;rst=1;
  wait(frames==2 && y==100);@(negedge clk);ready=1;brightness=0;
  wait(frames==3 && y==100);@(negedge clk);mode=1;brightness=64;
 end
 initial begin #85000000;$display("FAIL touch display timeout");$finish;end
endmodule
