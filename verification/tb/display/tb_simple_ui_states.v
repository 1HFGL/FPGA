`timescale 1ns/1ps
module tb_simple_ui_states;
    reg [11:0] x=0,y=0;
    reg [12:0] held=0;
    reg [1:0] octave=1;
    reg mode=0;
    wire [23:0] rgb;
    wire te;wire [5:0] glyph;
    integer o,k,s,f,midi,base,checks=0,found;
    integer open_notes[0:5];
    instrument_panel_ui dut(.x(x),.y(y),.key_down(held),.volume(7'd96),.pitch_bend(-16'sd32768),
        .octave(octave),.sustain(1'b0),.instrument_guitar(mode),.wave_ready(1'b0),
        .wave_min(16'sd0),.wave_max(16'sd0),.peak_level(16'd0),.gain_shift(4'd8),
        .activity(39'd0),.meter_level(16'd0),.meter_peak(16'd0),.text_enable(te),
        .text_glyph(glyph),.text_column(),.text_row(),.text_color(),.title_enable(),
        .title_glyph(),.title_column(),.title_row(),.base_rgb(rgb));
    initial begin
        open_notes[0]=64;open_notes[1]=59;open_notes[2]=55;
        open_notes[3]=50;open_notes[4]=45;open_notes[5]=40;
        for(o=0;o<3;o=o+1)begin
            octave=o;mode=0;held=0;
            x=92;y=540;#1;
            if(!te || glyph!=51+o)begin $display("FAIL piano first octave glyph");$finish;end
            x=932;#1;if(!te || glyph!=52+o)begin $display("FAIL piano last octave glyph");$finish;end
            mode=1;
            x=72;y=548;#1;if(!te || glyph!=51+o)begin $display("FAIL guitar first octave glyph");$finish;end
            x=960;#1;if(!te || glyph!=52+o)begin $display("FAIL guitar last octave glyph");$finish;end
            base=48+12*o;
            for(k=0;k<13;k=k+1)begin
                held=13'd1<<k;found=0;
                for(s=0;s<6;s=s+1)for(f=0;f<=12;f=f+1)begin
                    midi=open_notes[s]+f+(o==2?12:0);
                    x=128+f*64;y=392+s*24;#1;
                    if((rgb==24'hf0de6b)!==(midi==base+k))begin
                        $display("FAIL guitar map range=%0d key=%0d string=%0d fret=%0d rgb=%h",o,k,s,f,rgb);$finish;end
                    if(midi==base+k)found=found+1;
                    checks=checks+1;
                end
                if(found==0)begin $display("FAIL guitar note has no visible fret");$finish;end
            end
            held=0;
            for(f=0;f<=12;f=f+1)begin
                x=103+f*64;y=352;#1;
                if(o==2 && (!te || glyph!=(f<8?49:50)))begin $display("FAIL high fret tens");$finish;end
            end
        end
        $display("PASS tb_simple_ui_states: three ranges, both-mode octave labels, %0d independent fret checks, every note visible, high frets",checks);$finish;
    end
endmodule
