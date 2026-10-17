// 1024x600“静奏”绘制描述：不含帧缓存，所有坐标为编译期固定布局。
// 钢琴用键盘，吉他用标准调弦0..12品指位示意；同音可用位置一起高亮。
// 文本交给一拍同步字库，背景/坐标由instrument_display统一流水。
module instrument_panel_renderer(
    input wire [11:0] x,y,
    input wire [12:0] key_down,
    input wire [6:0] volume,
    input wire signed [15:0] pitch_bend,
    input wire [1:0] octave,
    input wire sustain,instrument_guitar,wave_ready,
    input wire signed [15:0] wave_min,wave_max,
    input wire [15:0] peak_level,
    input wire [3:0] gain_shift,
    output reg [23:0] base_rgb,text_color,
    output reg [5:0] text_glyph,
    output reg [4:0] text_column,text_row,
    output reg text_enable
);
    wire [23:0] background=instrument_guitar?24'h18130f:24'h0c141e;
    wire [23:0] panel=instrument_guitar?24'h251e18:24'h152331;
    wire [23:0] accent=instrument_guitar?24'hf0b76b:24'h65d9ed;
    wire [23:0] grid=instrument_guitar?24'h483728:24'h2a4054;
    localparam [23:0] TEXT=24'he8edf2,MUTED=24'ha4b4c3;
    wire signed [31:0] low_amp=$signed({{16{wave_min[15]}},wave_min}) <<< gain_shift;
    wire signed [31:0] high_amp=$signed({{16{wave_max[15]}},wave_max}) <<< gain_shift;
    wire signed [31:0] low_shifted=low_amp>>>9,high_shifted=high_amp>>>9;
    wire signed [17:0] low_step=(low_amp>32767)?18'sd63:
        ((low_amp < -32768)?-18'sd64:low_shifted[17:0]);
    wire signed [17:0] high_step=(high_amp>32767)?18'sd63:
        ((high_amp < -32768)?-18'sd64:high_shifted[17:0]);
    wire [17:0] wave_top_wide=18'sd284-high_step,wave_bottom_wide=18'sd284-low_step;
    wire [11:0] wave_top=wave_top_wide[11:0],wave_bottom=wave_bottom_wide[11:0];
    wire [7:0] level_height=peak_level[15:8]; // 0..128，直接反映数字输出峰值
    wire [15:0] bend_abs=pitch_bend[15]?(~pitch_bend+16'd1):pitch_bend;
    wire [23:0] bend_wide={8'd0,bend_abs};
    wire [23:0] bend_scaled=(bend_wide<<7)+(bend_wide<<6)+(bend_wide<<3)+24'd16384;
    wire [7:0] bend_cents=bend_scaled[22:15];
    wire [8:0] multiplier=9'd1<<gain_shift;
    function [11:0] decimal_digits;
        input [8:0] value;
        reg [11:0] digits;
        integer b;
        begin
            digits=0;
            for(b=8;b>=0;b=b-1)begin
                if(digits[3:0]>=5)digits[3:0]=digits[3:0]+4'd3;
                if(digits[7:4]>=5)digits[7:4]=digits[7:4]+4'd3;
                if(digits[11:8]>=5)digits[11:8]=digits[11:8]+4'd3;
                digits={digits[10:0],value[b]};
            end
            decimal_digits=digits;
        end
    endfunction
    function [5:0] dg;
        input [3:0] value;
        begin case(value)0:dg=28;8:dg=29;9:dg=30;default:dg=20+value;endcase end
    endfunction
    wire [11:0] volume_digits=decimal_digits({2'd0,volume});
    wire [11:0] bend_digits=decimal_digits({1'b0,bend_cents});
    wire [11:0] gain_digits=decimal_digits(multiplier);
    wire [23:0] gain_label=(multiplier<10)?{6'd57,dg(gain_digits[3:0]),12'd0}:
        ((multiplier<100)?{6'd57,dg(gain_digits[7:4]),dg(gain_digits[3:0]),6'd0}:
                         {6'd57,dg(gain_digits[11:8]),dg(gain_digits[7:4]),dg(gain_digits[3:0])});
    function integer white_note;
        input integer n;
        begin case(n)0:white_note=0;1:white_note=2;2:white_note=4;3:white_note=5;
            4:white_note=7;5:white_note=9;6:white_note=11;default:white_note=12;endcase end
    endfunction
    function [5:0] white_letter;
        input integer n;
        begin case(n)0,7:white_letter=50;1:white_letter=51;2:white_letter=52;
            3:white_letter=53;4:white_letter=54;5:white_letter=55;default:white_letter=56;endcase end
    endfunction
    function integer black_boundary;
        input integer n;
        begin case(n)0:black_boundary=1;1:black_boundary=2;2:black_boundary=4;
            3:black_boundary=5;default:black_boundary=6;endcase end
    endfunction
    function integer black_note;
        input integer n;
        begin case(n)0:black_note=1;1:black_note=3;2:black_note=6;
            3:black_note=8;default:black_note=10;endcase end
    endfunction
    function integer open_note;
        input integer n;
        begin case(n)0:open_note=64;1:open_note=59;2:open_note=55;
            3:open_note=50;4:open_note=45;default:open_note=40;endcase end
    endfunction
    function [5:0] string_letter;
        input integer n;
        begin case(n)0,5:string_letter=52;1:string_letter=56;2:string_letter=54;
            3:string_letter=51;default:string_letter=55;endcase end
    endfunction
    // 最多4字，26像素字距。固定比较替代除以26，避免像素路径的通用除法。
    task label4;
        input integer left,top,count;
        input [23:0] ids;
        input doubled;
        input [23:0] color;
        reg [11:0] lx,ly;
        reg [31:0] offset_x,offset_y;
        reg [1:0] slot;
        reg [5:0] glyph;
        begin
            offset_x={20'd0,x}-left;offset_y={20'd0,y}-top;
            lx=offset_x[11:0]>>doubled;ly=offset_y[11:0]>>doubled;slot=0;glyph=0;
            if(x>=left && y>=top && lx<count*26 && ly<24)begin
                if(lx>=78)begin slot=3;lx=lx-12'd78;end
                else if(lx>=52)begin slot=2;lx=lx-12'd52;end
                else if(lx>=26)begin slot=1;lx=lx-12'd26;end
                case(slot)0:glyph=ids[23:18];1:glyph=ids[17:12];2:glyph=ids[11:6];default:glyph=ids[5:0];endcase
                if(lx<24 && glyph!=0)begin
                    text_glyph=glyph;text_column=lx[4:0];text_row=ly[4:0];
                    text_enable=1;text_color=color;
                end
            end
        end
    endtask
    integer k,s,f,n,center_x,center_y;
    always @(*)begin
        base_rgb=background;text_color=TEXT;text_glyph=0;text_column=0;text_row=0;text_enable=0;
        n=0;center_x=0;center_y=0;
        // 顶部细线与分区卡片，保持内容优先、对比明确。
        if(x>=32 && x<992 && y>=82 && y<84)base_rgb=grid;
        if(x>=32 && x<336 && y>=96 && y<168)base_rgb=panel;
        if(x>=352 && x<704 && y>=96 && y<168)base_rgb=panel;
        if(x>=720 && x<992 && y>=96 && y<168)base_rgb=panel;
        if(x>=32 && x<992 && y>=184 && y<368)base_rgb=panel;
        if(x>=48 && x<816 && y>=216 && y<352)begin
            if(y==284 || x[6:0]==0)base_rgb=grid;
            if(wave_ready && y>=wave_top && y<=wave_bottom+1)base_rgb=accent;
        end
        if(x>=888 && x<920 && y>=216 && y<344)begin
            base_rgb=grid;
            if(y>=344-level_height)base_rgb=(peak_level>16'd30000)?24'hf17e72:accent;
        end
        if(x>=48 && x<304 && y>=152 && y<158)begin
            base_rgb=grid;if(x<48+{volume,1'b0})base_rgb=accent;
        end
        // 弯音中线、滑块；参数单位与原控制保持一致。
        if(x>=384 && x<672 && y>=152 && y<158)base_rgb=grid;
        if(x>=527 && x<530 && y>=146 && y<164)base_rgb=MUTED;
        if(x>=400+{~pitch_bend[15],pitch_bend[14:8]} &&
           x<406+{~pitch_bend[15],pitch_bend[14:8]} && y>=148 && y<162)base_rgb=accent;
        if(!instrument_guitar)begin
            for(k=0;k<8;k=k+1)begin
                if(x>=32+k*120 && x<151+k*120 && y>=400 && y<568)begin
                    base_rgb=key_down[white_note(k)]?24'h9fe4ee:24'hecece6;
                    if(y>=558)base_rgb=key_down[white_note(k)]?accent:24'hc2c9ca;
                end
            end
            for(k=0;k<5;k=k+1)begin
                if(x>=32+black_boundary(k)*120-36 && x<32+black_boundary(k)*120+36 && y>=400 && y<500)
                    base_rgb=key_down[black_note(k)]?accent:24'h0a1018;
            end
        end else begin
            if(x>=96 && x<928 && y>=404 && y<550)base_rgb=24'h34261d;
            for(f=0;f<=13;f=f+1)
                if(x>=96+f*64 && x<98+f*64 && y>=404 && y<550)base_rgb=24'h88715b;
            for(s=0;s<6;s=s+1)begin
                center_y=416+s*24;
                if(x>=96 && x<928 && y>=center_y && y<=center_y+(s>=3))base_rgb=24'hb6aa95;
                for(f=0;f<=12;f=f+1)begin
                    n=open_note(s)+f;center_x=128+f*64;
                    if(n>=60 && n<=72 && key_down[n-60] &&
                       x>=center_x-9 && x<=center_x+9 && y>=center_y-7 && y<=center_y+7)
                        base_rgb=accent;
                end
            end
        end
        label4(40,20,4,instrument_guitar?{6'd1,6'd2,6'd5,6'd6}:{6'd1,6'd2,6'd3,6'd4},1,TEXT);
        label4(884,34,2,{6'd32,6'd33,12'd0},0,accent);
        label4(48,108,2,{6'd7,6'd8,12'd0},0,MUTED);
        label4(226,108,3,{(volume<100?6'd0:dg(volume_digits[11:8])),
            (volume<10?6'd0:dg(volume_digits[7:4])),dg(volume_digits[3:0]),6'd0},0,TEXT);
        label4(384,108,2,{6'd9,6'd7,12'd0},0,MUTED);
        label4(550,108,1,{dg(bend_digits[11:8]),18'd0},0,TEXT);
        label4(584,108,2,{dg(bend_digits[7:4]),dg(bend_digits[3:0]),12'd0},0,TEXT);
        // +/-及小数点由矩形画出，不占中文字库槽。
        if(x>=526 && x<540 && y>=119 && y<122)base_rgb=accent;
        if(!pitch_bend[15] && x>=532 && x<535 && y>=113 && y<128)base_rgb=accent;
        if(x>=577 && x<581 && y>=128 && y<132)base_rgb=TEXT;
        label4(640,108,2,{6'd31,6'd7,12'd0},0,MUTED);
        label4(736,108,3,{(octave==0?6'd10:octave==2?6'd12:6'd11),6'd7,6'd13,6'd0},0,TEXT);
        label4(864,136,3,{6'd14,6'd7,(sustain?6'd15:6'd16),6'd0},0,MUTED);
        label4(48,186,4,{6'd17,6'd18,6'd19,6'd20},0,MUTED);
        label4(656,186,2,{6'd43,6'd44,12'd0},0,MUTED);
        label4(714,186,(multiplier<10?2:multiplier<100?3:4),gain_label,0,accent);
        label4(840,186,4,{6'd40,6'd41,6'd1,6'd42},0,MUTED);
        if(!instrument_guitar)begin
            label4(40,374,2,{6'd3,6'd4,12'd0},0,accent);
            for(k=0;k<8;k=k+1)
                label4(65+k*120,524,2,{white_letter(k),(k==7?6'd25:6'd24),12'd0},0,24'h304052);
        end else begin
            label4(40,374,4,{6'd36,6'd37,6'd38,6'd39},0,accent);
            for(s=0;s<6;s=s+1)
                label4(40,404+s*24,2,{string_letter(s),(s==0?6'd24:s<4?6'd23:6'd22),12'd0},0,MUTED);
            for(f=0;f<=12;f=f+1)begin
                if(f<10)label4(116+f*64,550,1,{dg(f[3:0]),18'd0},0,MUTED);
                else label4(103+f*64,550,2,{6'd21,dg(f[3:0]-4'd10),12'd0},0,MUTED);
            end
        end
    end
endmodule
