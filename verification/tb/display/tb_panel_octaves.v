`timescale 1ns/1ps
// Independent pixel-coordinate/glyph expectations across all 78 range/preset notes.
module tb_panel_octaves;
 reg [11:0] x=0,y=0;
 reg [12:0] keys=0;
 reg [1:0] oct=1;
 reg guitar=0;
 wire [23:0] rgb,old_rgb;
 wire text_on,old_text_on;
 wire [5:0] glyph,old_glyph;
 instrument_panel_ui dut(.x(x),.y(y),.key_down(keys),.volume(7'd32),.pitch_bend(16'd0),.octave(oct),
  .sustain(1'b0),.instrument_guitar(guitar),.wave_ready(1'b0),.wave_min(16'd0),.wave_max(16'd0),
  .peak_level(16'd0),.gain_shift(4'd0),.text_enable(text_on),.text_glyph(glyph),.text_column(),.text_row(),
  .text_color(),.title_enable(),.title_glyph(),.title_column(),.title_row(),.base_rgb(rgb));
 instrument_panel_renderer old_ui(.x(x),.y(y),.key_down(keys),.volume(7'd32),.pitch_bend(16'd0),.octave(oct),
  .sustain(1'b0),.instrument_guitar(guitar),.wave_ready(1'b0),.wave_min(16'd0),.wave_max(16'd0),
  .peak_level(16'd0),.gain_shift(4'd0),.text_enable(old_text_on),.text_glyph(old_glyph),
  .text_column(),.text_row(),.text_color(),.base_rgb(old_rgb));
 integer r,k,s,f,n,checks=0,matches,strings[0:5],white[0:7];
 reg expected;
 initial begin
  strings[0]=64;strings[1]=59;strings[2]=55;strings[3]=50;strings[4]=45;strings[5]=40;
  white[0]=0;white[1]=2;white[2]=4;white[3]=5;white[4]=7;white[5]=9;white[6]=11;white[7]=12;
  for(r=0;r<3;r=r+1)begin
   oct=r[1:0];guitar=0;
   x=736;y=100;#1;
   if(!text_on || glyph!=13+r)begin $display("FAIL range label glyph");$finish;end
   for(k=0;k<8;k=k+1)begin
    x=92+k*120;y=530;#1;
    if(!text_on || glyph!=51+r+(k==7))begin $display("FAIL piano octave label %0d %0d",r,k);$finish;end
    x=91+k*120;y=524;#1;
    if(!old_text_on || old_glyph!=23+r+(k==7))begin $display("FAIL legacy piano octave label");$finish;end
    keys=13'd1<<white[k];x=92+k*120;y=518;#1;
    if(rgb!==24'ha7e3ec)begin $display("FAIL piano highlight %h",rgb);$finish;end
   end
   guitar=1;
   for(k=0;k<13;k=k+1)begin
    keys=13'd1<<k;matches=0;
    for(s=0;s<6;s=s+1)for(f=0;f<=12;f=f+1)begin
     x=128+f*64;y=416+s*24;#1;
     n=strings[s]+f+(r==2?12:0);expected=(n==48+r*12+k);
     if((rgb===24'hf0b76b)!==expected || (old_rgb===24'hf0b76b)!==expected)
      begin $display("FAIL guitar fret map range=%0d key=%0d string=%0d fret=%0d",r,k,s,f);$finish;end
     if(expected)matches=matches+1;checks=checks+1;
    end
    if(matches==0)begin $display("FAIL invisible guitar note");$finish;end
   end
  end
  // High register shows 12..24, not a mislabeled open-string nut.
  oct=2;guitar=1;keys=0;x=104;y=550;#1;
  if(!text_on || glyph!=49)begin $display("FAIL fret12 tens");$finish;end
  x=130;#1;if(!text_on || glyph!=50)begin $display("FAIL fret12 ones");$finish;end
  x=872;#1;if(!text_on || glyph!=50)begin $display("FAIL fret24 tens");$finish;end
  x=898;#1;if(!text_on || glyph!=52)begin $display("FAIL fret24 ones");$finish;end
  $display("PASS tb_panel_octaves: all ranges, piano glyphs, %0d fret pixel checks, every guitar note visible, high fret labels",checks);$finish;
 end
endmodule
