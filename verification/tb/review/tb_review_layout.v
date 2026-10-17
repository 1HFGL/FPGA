`timescale 1ns/1ps
// 新增原生界面的独立检查，不修改队友已有测试平台。
module tb_review_layout;
    reg [11:0] x=0,y=0;
    reg [12:0] keys=0;
    reg [6:0] volume=0;
    reg signed [15:0] bend=0;
    wire [23:0] rgb;
    wire [5:0] glyph;
    integer i,d,bcd,mag,cents,white_index,black_index;
    piano_display_renderer #(.WIDE(1)) dut(.x(x),.y(y),.key_down(keys),.volume(volume),
        .pitch_bend(bend),.octave(2'd1),.sustain(1'b0),.instrument_guitar(1'b0),
        .wave_data(8'd0),.wave_ready(1'b0),.rgb(rgb),.text_glyph(glyph),
        .base_rgb(),.text_column(),.text_row(),.text_enable(),.text_color());
    task pixel;
        input integer px,py;
        input [23:0] color;
        begin x=px;y=py;#1;if(rgb!==color)begin
            $display("FAIL native pixel %0d,%0d expected=%h got=%h",px,py,color,rgb);$finish;end end
    endtask
    function integer glyph_digit;
        input [5:0] id;
        begin case(id)
            28:glyph_digit=0;29:glyph_digit=8;30:glyph_digit=9;
            default:glyph_digit=id-20;
        endcase end
    endfunction
    initial begin
        // 参考采用除法和余数，独立于RTL的移位加3算法。
        for(i=0;i<256;i=i+1)begin
            bcd=(i/100)*256+((i/10)%10)*16+i%10;
            if(dut.decimal_digits(i[7:0])!==bcd[11:0])begin $display("FAIL decimal %0d",i);$finish;end
        end
        // 验证所有音量码以及实际数字输出端，防止内部数值正确、字符接错。
        for(i=0;i<128;i=i+1)begin
            volume=i[6:0];y=108;
            for(d=0;d<3;d=d+1)begin
                x=240+d*24;#1;
                case(d)0:bcd=i/100;1:bcd=(i/10)%10;default:bcd=i%10;endcase
                if((d==0 && i<100)||(d==1 && i<10))begin
                    if(glyph!==0)begin $display("FAIL volume leading zero %0d",i);$finish;end
                end else if(glyph_digit(glyph)!=bcd)begin $display("FAIL volume glyph %0d",i);$finish;end
            end
        end
        for(i=-32768;i<32768;i=i+1)begin
            bend=i;#1;mag=(i<0)?-i:i;cents=(mag*200+16384)/32768;
            if(dut.bend_cents!==cents[7:0])begin $display("FAIL bend rounded %0d",i);$finish;end
        end
        bend=-32768;x=472;y=108;#1;
        if(glyph_digit(glyph)!=2)begin $display("FAIL bend -2.00");$finish;end
        pixel(456,114,24'h1a2327); // 负号不得多出竖线
        bend=-1;pixel(456,114,24'he9b879); // 消除显示负零
        x=592;y=108;#1;if(glyph!==31)begin $display("FAIL semitone unit half");$finish;end
        x=618;#1;if(glyph!==7)begin $display("FAIL semitone unit tone");$finish;end
        // 标签最后一个字后不能因固定字槽地址回绕重复首字。
        pixel(155,230,24'h151e22);
        for(i=0;i<13;i=i+1)begin
            keys=13'd1<<i;
            case(i)0:white_index=0;2:white_index=1;4:white_index=2;5:white_index=3;
                7:white_index=4;9:white_index=5;11:white_index=6;12:white_index=7;default:white_index=-1;endcase
            case(i)1:black_index=1;3:black_index=2;6:black_index=4;8:black_index=5;10:black_index=6;default:black_index=-1;endcase
            if(white_index>=0)begin
                pixel(92+white_index*120,500,24'ha8decf);keys=0;pixel(92+white_index*120,500,24'hf0ede5);
            end
            if(black_index>=0)begin
                pixel(32+black_index*120,400,24'he9b879);keys=0;pixel(32+black_index*120,400,24'h202c3b);
            end
        end
        // E/F与B/C无黑键；两端琴键没有溢出画布。
        pixel(394,400,24'hf0ede5);pixel(874,400,24'hf0ede5);
        pixel(990,500,24'hf0ede5);pixel(992,500,24'h080d14);
        pixel(0,0,24'h101619);pixel(1023,599,24'h101619);
        volume=0;pixel(40,160,24'h303d42);
        volume=127;pixel(293,160,24'h5bd6bb);pixel(294,160,24'h303d42);
        $display("PASS tb_review_layout: all volume/bend numeric codes, 13 keys, signs, native bounds");$finish;
    end
    initial begin #1000000;$display("FAIL layout timeout");$finish;end
endmodule
