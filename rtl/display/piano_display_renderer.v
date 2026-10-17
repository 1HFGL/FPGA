// 组合像素绘制器；WIDE=1适配1024x600，默认800x480供通用入口使用。
// 上部音色/音量/弯音/八度/延音，中部波形，下部8白键+5黑键，共13个半音。
// 使用区域比较和小字库；没有整屏RAM、除法器或处理器绘图任务。
module piano_display_renderer #(parameter integer WIDE=0) (
    input wire [11:0] x,y,
    input wire [12:0] key_down,
    input wire [6:0] volume,
    input wire signed [15:0] pitch_bend,
    input wire [1:0] octave,
    input wire sustain, instrument_guitar,
    input wire [7:0] wave_data,
    input wire wave_ready,
    output reg [23:0] rgb,
    // 给生产显示流水线的绘制描述；rgb仍用于原组合绘制器检查。
    output reg [23:0] base_rgb,
    output wire [5:0] text_glyph,
    output wire [4:0] text_column,text_row,
    output reg text_enable,
    output reg [23:0] text_color
);
    localparam [23:0] BG=WIDE?24'h101619:24'h0b1220, PANEL=WIDE?24'h1a2327:24'h142238, GRID=WIDE?24'h303d42:24'h30435b;
    localparam [23:0] TEXT=WIDE?24'he7ecef:24'he1eaf5, ACCENT=WIDE?24'h5bd6bb:24'h35dfb2, AMBER=WIDE?24'he9b879:24'hffb454;
    localparam [23:0] WHITE_KEY=WIDE?24'hf0ede5:24'he7edf5, BLACK_KEY=WIDE?24'h131b26:24'h172338;
    localparam [23:0] HELD_WHITE=WIDE?24'ha8decf:ACCENT;
    localparam [23:0] MUTED=WIDE?24'h9aaeb3:TEXT;
    // 编译期布局常量，不引入坐标缩放器或整屏缓存。两种尺寸共享唯一绘制逻辑。
    localparam [11:0] VOL_X=WIDE?12'd40:12'd32, BEND_X=WIDE?12'd368:12'd352;
    localparam [11:0] LABEL_Y=WIDE?12'd108:12'd56, BAR_Y=WIDE?12'd160:12'd90;
    localparam [11:0] STATE_X=WIDE?12'd712:12'd640;
    localparam [11:0] WAVE_X=WIDE?12'd256:12'd144, WAVE_MID=WIDE?12'd276:12'd196;
    localparam [11:0] KEY_X=WIDE?12'd32:12'd48, KEY_W=WIDE?12'd120:12'd88;
    localparam [11:0] KEY_Y=WIDE?12'd352:12'd280, KEY_END=WIDE?12'd568:12'd456;
    localparam [11:0] BLACK_HALF=WIDE?12'd36:12'd26, BLACK_END=WIDE?12'd482:12'd386;
    localparam [11:0] DIGIT_Y=WIDE?12'd528:12'd423;
    localparam [11:0] DIGIT_X=KEY_X+(KEY_W-12'd24)/12'd2;
    integer k;
    // 每组最多4字，每字6位编号；字形编号见 display_font24.v。
    reg [23:0] label_ids;
    reg [11:0] text_x,text_y;
    wire [4:0] glyph_offset={1'b0,text_x[6:5],2'b0}+{2'b0,text_x[6:5],1'b0};
    wire [5:0] glyph_id=label_ids[5'd23-glyph_offset -: 6];
    assign text_glyph=glyph_id;
    assign text_column=text_x[4:0];assign text_row=text_y[4:0];
    wire glyph_ink;
    wire [11:0] wave_y=(WAVE_MID+12'd32)-{6'd0,~wave_data[7],wave_data[6:2]};
    wire [11:0] volume_end=VOL_X+{4'd0,volume,1'b0};
    // 翻转符号位把补码 -32768..32767 映射为屏幕左..右的0..255。
    wire [11:0] bend_x=BEND_X+{4'd0,~pitch_bend[15],pitch_bend[14:8]};
    display_font24 u_font(.pixel_clk(1'b0),.glyph_id(glyph_id),.column(text_x[4:0]),.row(text_y[4:0]),.ink(glyph_ink));

    function [3:0] white_note;
        input integer index;
        begin
            case(index)
                0:white_note=0; 1:white_note=2; 2:white_note=4; 3:white_note=5;
                4:white_note=7; 5:white_note=9; 6:white_note=11; default:white_note=12;
            endcase
        end
    endfunction
    function [5:0] white_digit;
        input integer index;
        begin
            case(index)
                1:white_digit=22; 2:white_digit=23; 3:white_digit=24;
                4:white_digit=25; 5:white_digit=26; 6:white_digit=27;
                default:white_digit=21;
            endcase
        end
    endfunction
    function [11:0] digit_left;
        input integer index;
        begin digit_left=DIGIT_X+{9'd0,index[2:0]}*KEY_W; end
    endfunction

    // 把紧凑显示坐标重映射到原32像素字库槽；字体接口和ROM均保持不变。
    // 中文26像素字距（24像素字形+2像素留白），数字24像素等宽。
    function [11:0] chinese_x;
        input [11:0] offset;
        begin
            if(offset<26)chinese_x=offset;
            else if(offset<52)chinese_x=offset+12'd6;
            else if(offset<78)chinese_x=offset+12'd12;
            else chinese_x=offset+12'd18;
        end
    endfunction
    function [11:0] numeric_x;
        input [11:0] offset;
        begin
            if(offset<24)numeric_x=offset;
            else if(offset<48)numeric_x=offset+12'd8;
            else if(offset<72)numeric_x=offset+12'd16;
            else numeric_x=offset+12'd24;
        end
    endfunction

    // 8位数转十进制：固定8步移位加3，不使用综合代价较高的十进制除法。
    function [11:0] decimal_digits;
        input [7:0] value;
        reg [11:0] digits;
        integer bit_no;
        begin
            digits=0;
            for(bit_no=7;bit_no>=0;bit_no=bit_no-1)begin
                if(digits[3:0]>=5)digits[3:0]=digits[3:0]+4'd3;
                if(digits[7:4]>=5)digits[7:4]=digits[7:4]+4'd3;
                if(digits[11:8]>=5)digits[11:8]=digits[11:8]+4'd3;
                digits={digits[10:0],value[bit_no]};
            end
            decimal_digits=digits;
        end
    endfunction
    function [5:0] digit_glyph;
        input [3:0] digit;
        begin
            case(digit)
                0:digit_glyph=28; 8:digit_glyph=29; 9:digit_glyph=30;
                default:digit_glyph=6'd20+{2'd0,digit};
            endcase
        end
    endfunction
    // 屏幕显示目标值：音量0..127；弯音显示半音，四舍五入到0.01半音。
    // abs(-32768)必须保留无符号16位，不能再解释成负数。
    wire [15:0] bend_abs=pitch_bend[15] ? (~pitch_bend+16'd1) : pitch_bend;
    wire [23:0] bend_wide={8'd0,bend_abs};
    wire [23:0] bend_scaled=(bend_wide<<7)+(bend_wide<<6)+(bend_wide<<3)+24'd16384;
    wire [7:0] bend_cents=bend_scaled[22:15];
    wire [11:0] volume_digits=decimal_digits({1'b0,volume});
    wire [11:0] bend_digits=decimal_digits(bend_cents);
    function integer black_boundary;
        input integer index;
        begin
            case(index)
                0:black_boundary=1; 1:black_boundary=2; 2:black_boundary=4;
                3:black_boundary=5; default:black_boundary=6;
            endcase
        end
    endfunction
    function [3:0] black_note;
        input integer index;
        begin
            case(index)
                0:black_note=1; 1:black_note=3; 2:black_note=6;
                3:black_note=8; default:black_note=10;
            endcase
        end
    endfunction

    always @(*) begin
        // 默认值覆盖所有输出/中间量，区域以外不保留上一个像素，避免锁存器。
        rgb=BG; label_ids=0; text_x=0; text_y=0;
        text_enable=1'b0; text_color=TEXT;
        if (!WIDE && x>=16 && x<784 && y>=48 && y<124) rgb=PANEL;
        if (WIDE)begin
            if(y==72 && x>=24 && x<1000)rgb=GRID;
            if(y>=88 && y<192 && x>=24 && x<1000)rgb=PANEL;
            if(y>=104 && y<176 && (x==344 || x==680))rgb=GRID;
            // 琴键底座和细毡条，增加乐器的层次感；均为常量区域比较。
            if(x>=24 && x<1000 && y>=340 && y<576)rgb=24'h080d14;
            if(x>=32 && x<992 && y>=348 && y<352)rgb=24'h80684b;
            // 标题右侧保留留白，避免装饰条被误读为未接通的电平计。
        end
        if (x>=(WIDE?24:32) && x<(WIDE?1000:768) && y>=(WIDE?208:136) && y<(WIDE?328:256)) begin
            rgb=WIDE?24'h151e22:PANEL;
            if (!WIDE && (y==WAVE_MID || (x>=WAVE_X && x<WAVE_X+512 && x[5:0]==16))) rgb=GRID;
            if (WIDE && x>=WAVE_X && x<WAVE_X+512 && y>=232 && y<312 &&
                (y==WAVE_MID || x[6:0]==0))rgb=24'h26363b;
        end
        if (x>=VOL_X && x<VOL_X+256 && y>=BAR_Y && y<BAR_Y+(WIDE?8:20))
            rgb=(x<volume_end) ? ACCENT : GRID;
        if (x>=BEND_X && x<BEND_X+256 && y>=BAR_Y && y<BAR_Y+(WIDE?8:20)) begin
            rgb=GRID;
            if (x==BEND_X+128) rgb=TEXT;
            if (x==bend_x || x==bend_x+1'b1) rgb=AMBER;
        end
        if (wave_ready && x>=WAVE_X && x<WAVE_X+512 && (y==wave_y || y==wave_y+1'b1)) rgb=ACCENT;

        // 白键先画，黑键后画以覆盖上半部；E/F、B/C之间没有黑键。
        for (k=0;k<8;k=k+1) begin
            if (x>=KEY_X+k*KEY_W && x<KEY_X+(k+1)*KEY_W && y>=KEY_Y && y<KEY_END) begin
                rgb=key_down[white_note(k)] ? HELD_WHITE : WHITE_KEY;
                if (x==KEY_X+k*KEY_W || x==KEY_X+(k+1)*KEY_W-1 || y==KEY_Y || y==KEY_END-1) rgb=GRID;
                if(WIDE && y>=KEY_END-6 && x>KEY_X+k*KEY_W && x<KEY_X+(k+1)*KEY_W-1)rgb=key_down[white_note(k)]?ACCENT:24'hc8c6be;
            end
        end
        for (k=0;k<5;k=k+1) begin
            if (x>=KEY_X+black_boundary(k)*KEY_W-BLACK_HALF && x<KEY_X+black_boundary(k)*KEY_W+BLACK_HALF && y>=KEY_Y && y<BLACK_END)begin
                rgb=key_down[black_note(k)] ? AMBER : BLACK_KEY;
                if(WIDE && !key_down[black_note(k)])begin
                    if(y<KEY_Y+5)rgb=24'h425064;
                    else if(y<BLACK_END-8)rgb=24'h202c3b;
                    if(x==KEY_X+black_boundary(k)*KEY_W-BLACK_HALF || x==KEY_X+black_boundary(k)*KEY_W+BLACK_HALF-1)rgb=24'h080d14;
                end
            end
        end

        // 原生界面收紧字符间距，通用800x480接口保留原坐标。
        if (x>=(WIDE?40:32) && x<(WIDE?248:160) && y>=(WIDE?16:12) && y<(WIDE?64:36)) begin
            text_enable=1'b1;
            // 标题2倍整数放大，同一字库无需额外ROM，也不引入像素插值。
            text_x=WIDE?chinese_x((x-12'd40)>>1):(x-12'd32);
            text_y=(y-(WIDE?12'd16:12'd12))>>(WIDE?1:0);
            label_ids=instrument_guitar ? {6'd1,6'd2,6'd5,6'd6} : {6'd1,6'd2,6'd3,6'd4};
        end else if (x>=VOL_X && x<VOL_X+64 && y>=LABEL_Y && y<LABEL_Y+24) begin
            text_enable=1'b1; text_x=x-VOL_X; text_y=y-LABEL_Y; label_ids={6'd7,6'd8,12'd0}; // 音量
            if(WIDE)begin text_x=chinese_x(x-VOL_X);text_color=MUTED;end
        end else if (x>=BEND_X && x<BEND_X+64 && y>=LABEL_Y && y<LABEL_Y+24) begin
            text_enable=1'b1; text_x=x-BEND_X; text_y=y-LABEL_Y; label_ids={6'd9,6'd7,12'd0}; // 弯音
            if(WIDE)begin text_x=chinese_x(x-BEND_X);text_color=MUTED;end
        end else if (x>=STATE_X && x<STATE_X+96 && y>=LABEL_Y && y<LABEL_Y+24) begin
            text_enable=1'b1; text_x=x-STATE_X; text_y=y-LABEL_Y;
            if(WIDE)text_x=chinese_x(x-STATE_X);
            case(octave)
                0:label_ids={6'd10,6'd7,6'd13,6'd0}; // 低音区
                2:label_ids={6'd12,6'd7,6'd13,6'd0}; // 高音区
                default:label_ids={6'd11,6'd7,6'd13,6'd0}; // 中音区
            endcase
        end else if (x>=STATE_X && x<STATE_X+96 && y>=BAR_Y && y<BAR_Y+24) begin
            text_enable=1'b1; text_x=x-STATE_X; text_y=y-BAR_Y;
            if(WIDE)text_x=chinese_x(x-STATE_X);
            label_ids=sustain ? {6'd14,6'd7,6'd15,6'd0} : {6'd14,6'd7,6'd16,6'd0}; // 延音开/关
            text_color=sustain ? ACCENT : MUTED;
        end else if (x>=(WIDE?40:48) && x<(WIDE?144:176) && y>=(WIDE?220:140) && y<(WIDE?244:164)) begin
            text_enable=1'b1; text_x=x-(WIDE?12'd40:12'd48); text_y=y-(WIDE?12'd220:12'd140); label_ids={6'd17,6'd18,6'd19,6'd20};
            if(WIDE)begin text_x=chinese_x(x-12'd40);text_color=MUTED;end
        end else if(WIDE && x>=240 && x<312 && y>=LABEL_Y && y<LABEL_Y+24)begin
            text_enable=1'b1;text_x=numeric_x(x-12'd240);text_y=y-LABEL_Y;text_color=ACCENT;
            label_ids={(volume>=100?digit_glyph(volume_digits[11:8]):6'd0),
                       (volume>=10?digit_glyph(volume_digits[7:4]):6'd0),digit_glyph(volume_digits[3:0]),6'd0};
        end else if(WIDE && x>=472 && x<568 && y>=LABEL_Y && y<LABEL_Y+24)begin
            text_enable=1'b1;text_x=numeric_x(x-12'd472);text_y=y-LABEL_Y;text_color=AMBER;
            label_ids={digit_glyph(bend_digits[11:8]),6'd0,digit_glyph(bend_digits[7:4]),digit_glyph(bend_digits[3:0])};
        end else if(WIDE && x>=592 && x<644 && y>=LABEL_Y && y<LABEL_Y+24)begin
            text_enable=1'b1;text_x=chinese_x(x-12'd592);text_y=y-LABEL_Y;
            label_ids={6'd31,6'd7,12'd0};text_color=MUTED; // 半音
        end
        // 符号和小数点由几何线条生成；小于0.005半音四舍五入为0时不显示负零。
        if(WIDE && ((x>=448 && x<464 && y>=119 && y<121) ||
            ((!pitch_bend[15] || bend_cents==0) && x>=455 && x<457 && y>=112 && y<128) ||
            (x>=503 && x<506 && y>=127 && y<130)))rgb=AMBER;
        for (k=0;k<8;k=k+1) begin
            if (x>=digit_left(k) && x<digit_left(k)+12'd24 && y>=DIGIT_Y && y<DIGIT_Y+24) begin
                text_enable=1'b1; text_x=x-digit_left(k); text_y=y-DIGIT_Y;
                label_ids={white_digit(k),18'd0}; text_color=BG;
            end
        end
        // 最右白键是上方八度的“1”，用高音点与最左端区分。
        if (x>=digit_left(7)+11 && x<digit_left(7)+14 && y>=DIGIT_Y-6 && y<DIGIT_Y-3) rgb=BG;
        base_rgb=rgb;
        if (text_enable && glyph_ink) rgb=text_color;
    end
endmodule
