// 固定800x480布局的组合像素绘制器。只做“某坐标是什么颜色”，不产生时钟。
// 上部音色/音量/弯音/八度/延音，中部波形，下部8白键+5黑键，共13个半音。
// 使用区域比较和小字库；没有整屏RAM、除法器或处理器绘图任务。
module piano_display_renderer (
    input wire [11:0] x,y,
    input wire [12:0] key_down,
    input wire [6:0] volume,
    input wire signed [15:0] pitch_bend,
    input wire [1:0] octave,
    input wire sustain, instrument_guitar,
    input wire [7:0] wave_data,
    input wire wave_ready,
    output reg [23:0] rgb
);
    localparam [23:0] BG=24'h0b1220, PANEL=24'h142238, GRID=24'h30435b;
    localparam [23:0] TEXT=24'he1eaf5, ACCENT=24'h35dfb2, AMBER=24'hffb454;
    localparam [23:0] WHITE_KEY=24'he7edf5, BLACK_KEY=24'h172338;
    integer k;
    // 每组最多4字，每字6位编号；字形编号见 display_font24.v。
    reg [23:0] label_ids;
    reg [11:0] text_x,text_y;
    reg text_enable;
    reg [23:0] text_color;
    wire [4:0] glyph_offset={1'b0,text_x[6:5],2'b0}+{2'b0,text_x[6:5],1'b0};
    wire [5:0] glyph_id=label_ids[5'd23-glyph_offset -: 6];
    wire glyph_ink;
    wire [11:0] wave_y=12'd228-{6'd0,~wave_data[7],wave_data[6:2]};
    wire [11:0] volume_end=12'd32+{4'd0,volume,1'b0};
    // 翻转符号位把补码 -32768..32767 映射为屏幕左..右的0..255。
    wire [11:0] bend_x=12'd352+{4'd0,~pitch_bend[15],pitch_bend[14:8]};
    display_font24 u_font(.glyph_id(glyph_id),.column(text_x[4:0]),.row(text_y[4:0]),.ink(glyph_ink));

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
        begin digit_left=12'd80+{9'd0,index[2:0]}*12'd88; end
    endfunction
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
        if (x>=16 && x<784 && y>=48 && y<124) rgb=PANEL;
        if (x>=32 && x<768 && y>=136 && y<256) begin
            rgb=PANEL;
            if (y==196 || (x>=144 && x<656 && x[5:0]==16)) rgb=GRID;
        end
        if (x>=32 && x<288 && y>=90 && y<110)
            rgb=(x<volume_end) ? ACCENT : GRID;
        if (x>=352 && x<608 && y>=90 && y<110) begin
            rgb=GRID;
            if (x==480) rgb=TEXT;
            if (x==bend_x || x==bend_x+1'b1) rgb=AMBER;
        end
        if (wave_ready && x>=144 && x<656 && (y==wave_y || y==wave_y+1'b1)) rgb=ACCENT;

        // 白键先画，黑键后画以覆盖上半部；E/F、B/C之间没有黑键。
        for (k=0;k<8;k=k+1) begin
            if (x>=48+k*88 && x<136+k*88 && y>=280 && y<456) begin
                rgb=key_down[white_note(k)] ? ACCENT : WHITE_KEY;
                if (x==48+k*88 || x==135+k*88 || y==280 || y==455) rgb=GRID;
            end
        end
        for (k=0;k<5;k=k+1) begin
            if (x>=48+black_boundary(k)*88-26 && x<48+black_boundary(k)*88+26 && y>=280 && y<386)
                rgb=key_down[black_note(k)] ? AMBER : BLACK_KEY;
        end

        // 中文24x24字形、32像素字间距。标题和状态均为汉字，键帽使用简谱数字。
        if (x>=32 && x<160 && y>=12 && y<36) begin
            text_enable=1'b1; text_x=x-12'd32; text_y=y-12'd12;
            label_ids=instrument_guitar ? {6'd1,6'd2,6'd5,6'd6} : {6'd1,6'd2,6'd3,6'd4};
        end else if (x>=32 && x<96 && y>=56 && y<80) begin
            text_enable=1'b1; text_x=x-12'd32; text_y=y-12'd56; label_ids={6'd7,6'd8,12'd0}; // 音量
        end else if (x>=352 && x<416 && y>=56 && y<80) begin
            text_enable=1'b1; text_x=x-12'd352; text_y=y-12'd56; label_ids={6'd9,6'd7,12'd0}; // 弯音
        end else if (x>=640 && x<736 && y>=56 && y<80) begin
            text_enable=1'b1; text_x=x-12'd640; text_y=y-12'd56;
            case(octave)
                0:label_ids={6'd10,6'd7,6'd13,6'd0}; // 低音区
                2:label_ids={6'd12,6'd7,6'd13,6'd0}; // 高音区
                default:label_ids={6'd11,6'd7,6'd13,6'd0}; // 中音区
            endcase
        end else if (x>=640 && x<736 && y>=90 && y<114) begin
            text_enable=1'b1; text_x=x-12'd640; text_y=y-12'd90;
            label_ids=sustain ? {6'd14,6'd7,6'd15,6'd0} : {6'd14,6'd7,6'd16,6'd0}; // 延音开/关
            text_color=sustain ? ACCENT : TEXT;
        end else if (x>=48 && x<176 && y>=140 && y<164) begin
            text_enable=1'b1; text_x=x-12'd48; text_y=y-12'd140; label_ids={6'd17,6'd18,6'd19,6'd20};
        end
        for (k=0;k<8;k=k+1) begin
            if (x>=digit_left(k) && x<digit_left(k)+12'd24 && y>=423 && y<447) begin
                text_enable=1'b1; text_x=x-digit_left(k); text_y=y-12'd423;
                label_ids={white_digit(k),18'd0}; text_color=BG;
            end
        end
        // 最右白键是上方八度的“1”，用高音点与最左端区分。
        if (x>=707 && x<710 && y>=417 && y<420) rgb=BG;
        if (text_enable && glyph_ink) rgb=text_color;
    end
endmodule
