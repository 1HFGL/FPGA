`timescale 1ns/1ps
module tb_display_renderer;
    reg [11:0] x=0,y=0;
    reg [12:0] keys=0;
    reg [6:0] volume=0;
    reg signed [15:0] bend=0;
    reg [1:0] octave=1;
    reg sustain=0,guitar=0,wr=0;
    reg [7:0] wave=0;
    wire [23:0] rgb;
    integer i,wx,bx;
    piano_display_renderer dut(.x(x),.y(y),.key_down(keys),.volume(volume),.pitch_bend(bend),
        .octave(octave),.sustain(sustain),.instrument_guitar(guitar),.wave_data(wave),.wave_ready(wr),.rgb(rgb));
    task pixel;
        input integer px,py;
        input [23:0] expected;
        begin
            x=px;y=py;#1;
            if(rgb!==expected) begin $display("FAIL render (%0d,%0d) expected=%h got=%h",x,y,expected,rgb);$finish;end
        end
    endtask
    initial begin
        // 13个半音逐个检查，白键检查下半部，黑键检查与白键相交的上半部。
        for(i=0;i<13;i=i+1) begin
            keys=13'd1<<i;
            case(i)
                0:wx=0;2:wx=1;4:wx=2;5:wx=3;7:wx=4;9:wx=5;11:wx=6;12:wx=7;default:wx=-1;
            endcase
            case(i)
                1:bx=1;3:bx=2;6:bx=4;8:bx=5;10:bx=6;default:bx=-1;
            endcase
            if(wx>=0) begin pixel(80+wx*88,410,24'h35dfb2);keys=0;pixel(80+wx*88,410,24'he7edf5);end
            if(bx>=0) begin pixel(48+bx*88,310,24'hffb454);keys=0;pixel(48+bx*88,310,24'h172338);end
        end
        // E/F与B/C交界不应出现黑键；检查键边框之外的像素。
        pixel(48+3*88+2,310,24'he7edf5);pixel(48+7*88+2,310,24'he7edf5);
        volume=0;pixel(32,100,24'h30435b);
        volume=127;pixel(285,100,24'h35dfb2);pixel(286,100,24'h30435b);
        bend=-32768;pixel(352,100,24'hffb454);
        bend=0;pixel(480,100,24'hffb454);
        bend=32767;pixel(607,100,24'hffb454);pixel(608,100,24'h142238);
        wr=1;wave=8'h80;pixel(200,228,24'h35dfb2);
        wave=8'h7f;pixel(200,165,24'h35dfb2);
        wave=0;pixel(200,196,24'h35dfb2);wr=0;pixel(200,196,24'h30435b);
        // “电子钢琴/电子吉他”的第三字，检查字库中钢有墨而吉无墨的位置。
        guitar=0;pixel(100,13,24'he1eaf5);guitar=1;pixel(100,13,24'h0b1220);
        sustain=1;pixel(658,91,24'h35dfb2);sustain=0;pixel(658,91,24'he1eaf5);
        $display("PASS tb_display_renderer: 13 keys, priority, volume/bend bounds, signed wave, timbres");$finish;
    end
endmodule
