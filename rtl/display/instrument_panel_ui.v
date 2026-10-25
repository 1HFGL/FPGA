// 1024x600“静奏·简洁版”：暖白底、淡黄反馈、真实波形和双乐器主体。
// 与 instrument_panel_renderer 的区别：
//   - 文本分两个层次：24px 正文与 48px 原生标题，不再把 24px 点阵整数放大；
//   - 字形以覆盖度 0..3 表示，由上层与背景做一次线性混合，边缘平滑；
//   - 钢琴键盘与吉他指板共用同一网格与配色体系，主体形态各自体现乐器。
// 默认组合绘制；正式入口仅在帧提交沿预存弯音数字，坐标仍为编译期常量。
// 不含除法、开方或整屏帧缓存，像素请求流水线不增加拍数。
// 文本接口：本模块在 P0 给出字形/行/列请求，字模 ROM 在 P1 返回整行覆盖度。
module instrument_panel_ui #(
    // 保留队友触摸准备版的接口兼容；当前简洁布局不叠加旧版顶部滑条。
    // USB主机尚未接通，不能把不可用的控件画成已经能操作。
    parameter integer TOUCH_PANEL=0,
    parameter integer ENABLE_GUIDE=0,
    parameter integer LOG_METER=0,
    parameter integer SHOW_BRIGHTNESS=0,
    parameter [23:0] C_BG      = 24'hecebe7,
    parameter [23:0] C_PANEL   = 24'hf8f7f3,
    parameter [23:0] C_GRID    = 24'hd7d6d0,
    parameter [23:0] C_TEXT    = 24'h252c2e,
    parameter [23:0] C_MUTED   = 24'h686e70,
    parameter [23:0] C_ACCENT  = 24'hf0de6b,
    parameter [23:0] C_WARM    = 24'hf0de6b,
    parameter integer FRAME_BEND=0
) (
    input wire [11:0] x, y,
    input wire [12:0] key_down,
    input wire [6:0] volume,brightness,
    input wire touch_available,
    input wire signed [15:0] pitch_bend,
    input wire [1:0] octave,
    input wire sustain, instrument_guitar,
    input wire guide_valid,
    input wire [3:0] guide_index,guide_progress,
    input wire wave_ready,
    input wire signed [15:0] wave_min, wave_max,
    input wire [15:0] peak_level,
    input wire [3:0] gain_shift,
    input wire [38:0] activity,
    input wire [15:0] meter_level,meter_peak,
    input wire [7:0] meter_height,meter_peak_height,
    // 24px 正文请求
    output reg text_enable,
    output reg [5:0] text_glyph,
    output reg [4:0] text_column, text_row,
    output reg [23:0] text_color,
    // 48px 标题请求
    output reg title_enable,
    output reg [2:0] title_glyph,
    output reg [5:0] title_column, title_row,
    // 该像素的底色
    output reg [23:0] base_rgb,
    // FRAME_BEND=1时与上层状态快照同沿提交；默认组合实例无需时钟。
    input wire pixel_clk, pixel_rst_n, frame_commit,
    input wire signed [15:0] pitch_bend_latest
);
    // 配色随音色切换；两套界面共用同一布局网格。
    wire [23:0] accent = instrument_guitar ? C_WARM : C_ACCENT;
    wire [23:0] bg=C_BG, panel=C_PANEL, grid=C_GRID;
    wire note_hit,key_black;
    wire [3:0] key_index;
    wire [11:0] key_left,key_right,key_top,key_bottom;
    wire [1:0] control_kind,control_value;
    instrument_ui_map u_map(.x(x),.y(y),.instrument_guitar(instrument_guitar),
        .note_valid(note_hit),.note_index(key_index),.key_black(key_black),
        .key_left(key_left),.key_right(key_right),.key_top(key_top),.key_bottom(key_bottom),
        .control_kind(control_kind),.control_value(control_value));

    // Low range uses frets 0..12; high range scrolls to frets 12..24.
    // The high-range highlight layout equals middle shifted one octave.
    function guitar_held;
        input integer note;
        input [1:0] range_select;
        input [12:0] held;
        begin
            guitar_held=1'b0;
            if(range_select==0)begin
                if(note>=48 && note<=60)guitar_held=held[note-48];
            end else if(note>=60 && note<=72)guitar_held=held[note-60];
        end
    endfunction
    wire [5:0] first_octave_glyph=(octave==0)?6'd51:(octave==2)?6'd53:6'd52;
    wire [5:0] last_octave_glyph=first_octave_glyph+6'd1;
    // ---- 波形几何：512样本转256列min/max，中轴y=264，纵向约128像素 ----
    wire signed [31:0] low_amp  = $signed({{16{wave_min[15]}}, wave_min}) <<< gain_shift;
    wire signed [31:0] high_amp = $signed({{16{wave_max[15]}}, wave_max}) <<< gain_shift;
    wire signed [31:0] low_shifted  = low_amp  >>> 9;
    wire signed [31:0] high_shifted = high_amp >>> 9;
    // 超过满幅显示时饱和到 ±64 步，避免 12 位坐标回绕。
    wire signed [17:0] low_step  = (low_amp  >  32767) ?  18'sd63 :
                                   (low_amp  < -32768) ? -18'sd63 : low_shifted[17:0];
    wire signed [17:0] high_step = (high_amp >  32767) ?  18'sd63 :
                                   (high_amp < -32768) ? -18'sd63 : high_shifted[17:0];
    wire [11:0] wave_top    = 12'sd264 - high_step[11:0];
    wire [11:0] wave_bottom = 12'sd264 - low_step[11:0];
    wire [7:0] level_height=LOG_METER?meter_height:meter_level[15:8];
    wire [7:0] held_peak_height=LOG_METER?meter_peak_height:meter_peak[15:8];

    // ---- 数值格式化：每帧由上层更新一次，这里只做 BCD 选择 ----
    function [11:0] decimal_digits;
        input [8:0] value;
        reg [11:0] digits;
        integer b;
        begin
            digits = 0;
            for (b = 8; b >= 0; b = b - 1) begin
                if (digits[3:0]  >= 5) digits[3:0]  = digits[3:0]  + 4'd3;
                if (digits[7:4]  >= 5) digits[7:4]  = digits[7:4]  + 4'd3;
                if (digits[11:8] >= 5) digits[11:8] = digits[11:8] + 4'd3;
                digits = {digits[10:0], value[b]};
            end
            decimal_digits = digits;
        end
    endfunction
    // 数字字形编号：0..9 对应 48..57（47 是倍率符号 x），见 generate_ui_fonts.py。
    function [5:0] dg;
        input [3:0] value;
        begin dg = 6'd48 + value; end
    endfunction

    // 弯音显示：±2 半音，单位 0.01 半音。
    wire signed [15:0] bend_input = FRAME_BEND ? pitch_bend_latest : pitch_bend;
    wire [15:0] bend_abs = bend_input[15] ? (~bend_input + 16'd1) : bend_input;
    // (200*m+16384)>>15 等价于 (25*m+2048)>>12。
    // m最大32768（含-32768取绝对值），中间值最大821248，20位足够。
    wire [19:0] bend_scaled = {bend_abs,4'd0} + {1'b0,bend_abs,3'd0}
                            + {4'd0,bend_abs} + 20'd2048;
    wire [7:0] bend_cents = bend_scaled[19:12];

    wire [11:0] volume_digits = decimal_digits({2'd0, volume});
    wire [11:0] brightness_digits=decimal_digits({2'd0,brightness});
    // 0..127 occupies 0..318 pixels; shifts/addition only, no per-pixel divider.
    wire [11:0] brightness_position=12'd360+{4'd0,brightness,1'b0}+{6'd0,brightness[6:1]};
    wire [11:0] guide_digits=decimal_digits({5'd0,guide_progress});
    wire [8:0] guide_width={1'b0,guide_progress,4'd0}+{2'b0,guide_progress,3'd0};
    wire [11:0] guide_x=x-12'd360;
    wire [5:0] slash_sum={2'd0,x[3:0]}+{1'b0,y[4:0]};
    wire [11:0] bend_digits_next = decimal_digits({1'b0, bend_cents});
    wire [11:0] bend_digits;
    generate if(FRAME_BEND)begin:g_frame_bend
        reg [11:0] digits_q;
        always @(posedge pixel_clk or negedge pixel_rst_n)begin
            if(!pixel_rst_n)digits_q<=12'd0;
            else if(frame_commit)digits_q<=bend_digits_next;
        end
        assign bend_digits=digits_q;
    end else begin:g_comb_bend
        assign bend_digits=bend_digits_next;
    end endgenerate
    // 倍率只选三个固定字槽，不再参与字框宽度/文本使能的优先链。
    // 字形0表示空白；有效倍率为x1..x256，高于8仍显示x0，保持原边界行为。
    // 这样gain_shift仅经过字形选择进入ROM地址，不经过乘字宽/比较/覆盖仲裁。
    reg [17:0] gain_glyphs;
    always @* begin
        case(gain_shift)
            4'd0: gain_glyphs={6'd49,6'd0,6'd0};
            4'd1: gain_glyphs={6'd50,6'd0,6'd0};
            4'd2: gain_glyphs={6'd52,6'd0,6'd0};
            4'd3: gain_glyphs={6'd56,6'd0,6'd0};
            4'd4: gain_glyphs={6'd49,6'd54,6'd0};
            4'd5: gain_glyphs={6'd51,6'd50,6'd0};
            4'd6: gain_glyphs={6'd54,6'd52,6'd0};
            4'd7: gain_glyphs={6'd49,6'd50,6'd56};
            4'd8: gain_glyphs={6'd50,6'd53,6'd54};
            default: gain_glyphs={6'd48,6'd0,6'd0};
        endcase
    end

    // ---- 24px 正文：最多 4 字，字距 26（中文）/24（数字由调用处留空） ----
    // 用三次比较选槽位，避免在像素路径上放 /26 通用除法。
    task text4;
        // 坐标与字数都用 12 位/3 位端口：最多 4 字，2 位会截成 0。
        input [11:0] left, top;
        input [3:0] count;
        input [23:0] ids;
        input [23:0] color;
        reg [11:0] lx, ly;
        reg [11:0] limit;
        reg [1:0] slot;
        begin
            lx = x - left;
            ly = y - top;
            limit = count * 12'd26;
            if (x >= left && y >= top && lx < limit && ly < 24) begin
                if      (lx >= 78) begin slot = 3; lx = lx - 12'd78; end
                else if (lx >= 52) begin slot = 2; lx = lx - 12'd52; end
                else if (lx >= 26) begin slot = 1; lx = lx - 12'd26; end
                else                slot = 0;
                case (slot)
                    0: text_glyph = ids[23:18];
                    1: text_glyph = ids[17:12];
                    2: text_glyph = ids[11:6];
                    default: text_glyph = ids[5:0];
                endcase
                if (lx < 24 && text_glyph != 0) begin
                    text_enable = 1'b1;
                    text_column = lx[4:0];
                    text_row    = ly[4:0];
                    text_color  = color;
                end
            end
        end
    endtask

    // ---- 24px 数字：等宽字形本身 24px，用 24 字距，避免读数被撑成“9 6”。
    // 与 text4 结构相同，仅字距不同；两套比较都是常数，不引入除法器。
    task num4;
        input [11:0] left, top;
        input [3:0] count;
        input [23:0] ids;
        input [23:0] color;
        reg [11:0] lx, ly;
        reg [11:0] limit;
        reg [1:0] slot;
        begin
            lx = x - left;
            ly = y - top;
            limit = count * 12'd24;
            if (x >= left && y >= top && lx < limit && ly < 24) begin
                if      (lx >= 72) begin slot = 3; lx = lx - 12'd72; end
                else if (lx >= 48) begin slot = 2; lx = lx - 12'd48; end
                else if (lx >= 24) begin slot = 1; lx = lx - 12'd24; end
                else                slot = 0;
                case (slot)
                    0: text_glyph = ids[23:18];
                    1: text_glyph = ids[17:12];
                    2: text_glyph = ids[11:6];
                    default: text_glyph = ids[5:0];
                endcase
                if (lx < 24 && text_glyph != 0) begin
                    text_enable = 1'b1;
                    text_column = lx[4:0];
                    text_row    = ly[4:0];
                    text_color  = color;
                end
            end
        end
    endtask

    // ---- 48px 标题：字距 52，坐标右移一位得到 48x48 字形行列 ----
    task title4;
        input [11:0] left, top;
        input [3:0] count;
        input [17:0] ids; // 3 个 6bit 编号（本界面最多 4 字，第 4 字用两次调用）
        reg [11:0] lx, ly;
        reg [11:0] limit;
        reg [5:0] glyph;
        begin
            lx = x - left;
            ly = y - top;
            limit = count * 12'd52;
            // 字距 52、字形 48：每字右侧 4 像素是留白，必须落在字形之外，
            // 否则列号 48..51 会越过 96bit 行尾，取到未知值。
            if (x >= left && y >= top && lx < limit && ly < 48) begin
                if      (lx >= 104) begin glyph = ids[5:0];  lx = lx - 12'd104; end
                else if (lx >= 52)  begin glyph = ids[11:6]; lx = lx - 12'd52;  end
                else                begin glyph = ids[17:12]; end
                if (lx < 48) begin
                    title_enable = 1'b1;
                    title_glyph  = glyph[2:0];
                    title_column = lx[5:0];
                    title_row    = ly[5:0];
                end
            end
        end
    endtask

    function integer white_note;
        input integer n;
        begin
            case (n)
                0: white_note = 0;  1: white_note = 2;  2: white_note = 4;
                3: white_note = 5;  4: white_note = 7;  5: white_note = 9;
                6: white_note = 11; default: white_note = 12;
            endcase
        end
    endfunction
    function [5:0] white_letter;
        input integer n;
        begin
            case (n)
                0, 7: white_letter = 40; 1: white_letter = 41; 2: white_letter = 42;
                3: white_letter = 43;    4: white_letter = 44; 5: white_letter = 45;
                default: white_letter = 46;
            endcase
        end
    endfunction
    function integer black_boundary;
        input integer n;
        begin
            case (n)
                0: black_boundary = 1; 1: black_boundary = 2; 2: black_boundary = 4;
                3: black_boundary = 5; default: black_boundary = 6;
            endcase
        end
    endfunction
    function integer black_note;
        input integer n;
        begin
            case (n)
                0: black_note = 1; 1: black_note = 3; 2: black_note = 6;
                3: black_note = 8; default: black_note = 10;
            endcase
        end
    endfunction
    // 吉他标准调弦：E4 B3 G3 D3 A2 E2。
    function integer open_note;
        input integer n;
        begin
            case (n)
                0: open_note = 64; 1: open_note = 59; 2: open_note = 55;
                3: open_note = 50; 4: open_note = 45; default: open_note = 40;
            endcase
        end
    endfunction

    function [5:0] note_letter;
        input integer n;
        begin case(n)
            0,1,12:note_letter=40;2,3:note_letter=41;4:note_letter=42;
            5,6:note_letter=43;7,8:note_letter=44;9,10:note_letter=45;default:note_letter=46;
        endcase end
    endfunction
    function [2:0] note_activity;
        input integer note;
        input [1:0] range_select;
        input [38:0] levels;
        begin
            note_activity=0;
            if(range_select==0)begin
                if(note>=48 && note<=60)note_activity=levels[(note-48)*3+:3];
            end else if(note>=60 && note<=72)note_activity=levels[(note-60)*3+:3];
        end
    endfunction
    integer k,s,f,ny;
    always @(*) begin
        base_rgb=bg;
        text_enable=0;text_glyph=0;text_column=0;text_row=0;text_color=C_TEXT;
        title_enable=0;title_glyph=0;title_column=0;title_row=0;
        ny=0;

        // 暖白底与少量分隔。按钮命中区来自同一u_map，不再另写近似坐标。
        if(x>=16 && x<1008 && y>=12 && y<592)base_rgb=panel;
        if(x>=32 && x<992 && y==84)base_rgb=grid;
        if(control_kind!=0)begin
            base_rgb=24'he8e7e1;
            if((control_kind==1 && control_value=={1'b0,instrument_guitar}) ||
               (control_kind==2 && control_value==octave) ||
               (control_kind==3 && sustain))base_rgb=accent;
        end

        // 波形坐标仍是每列3像素/256列。填色与轨迹均来自真实有符号样本。
        if(x>=32 && x<992 && y>=160 && y<348)base_rgb=24'h293033;
        if(x>=48 && x<816 && y>=200 && y<332)begin
            if(y==264)base_rgb=24'h626963;
            if(wave_ready)begin
                if((y<=264 && y>=wave_top) || (y>=264 && y<=wave_bottom))
                    base_rgb=24'h777454;
                if(y+1>=wave_top && y<=wave_bottom+1)base_rgb=accent;
            end
        end
        // 正式电平条用固定对数刻度；原始峰值决定削波提示，波形倍率不影响它。
        if(x==856 && y>=176 && y<332)base_rgb=24'h596060;
        if(x>=904 && x<936 && y>=208 && y<336)begin
            base_rgb=24'h424a4c;
            if(y>=336-{4'd0,level_height})
                base_rgb=(peak_level>16'd30000)?24'he18b77:accent;
            if(y[2:0]==0)base_rgb=24'h293033;
            if((!LOG_METER || held_peak_height!=0) && y>=334-{4'd0,held_peak_height} &&
               y<337-{4'd0,held_peak_height})base_rgb=24'hf7f7ed;
        end

        // 键体高亮；短残影仅是显示反馈，key_down依然唯一表示正在持键。
        if(note_hit)begin
            if(key_black)base_rgb=key_down[key_index]?accent:24'h303638;
            else base_rgb=key_down[key_index]?24'hfaf2c6:24'hf5f4ef;
            if(!key_down[key_index] && activity[key_index*3+:3]!=0)
                base_rgb=key_black?24'h69664a:24'hf1edda;
            if(x==key_left || x+1==key_right || y==key_top || y+1==key_bottom)
                base_rgb=24'h6c7170;
            if(y+8>=key_bottom && key_down[key_index])base_rgb=accent;
            if(key_black && y<key_top+4)base_rgb=24'h565c5b;
            // 青绿空心边框表示下一目标；淡黄实心仍只表示实际按住。
            if(ENABLE_GUIDE && guide_valid && key_index==guide_index &&
               (x<key_left+3 || x+3>=key_right || y<key_top+3 || y+3>=key_bottom))
                base_rgb=24'h397e75;
        end
        if(instrument_guitar)begin
            if(x>=96 && x<928 && y>=384 && y<520)base_rgb=24'h333b3d;
            for(f=0;f<=13;f=f+1)
                if(x>=96+f*64 && x<98+f*64 && y>=384 && y<520)base_rgb=24'h8c9290;
            if(octave!=2 && x>=96 && x<102 && y>=384 && y<520)base_rgb=24'hc9cac2;
            for(s=0;s<6;s=s+1)begin
                ny=392+s*24;
                if(x>=102 && x<928 && y>=ny && y<=ny+(s>=4))base_rgb=24'hacb2ac;
                for(f=0;f<=12;f=f+1)begin
                    if(guitar_held(open_note(s)+f,octave,key_down))begin
                        if(x>=119+f*64 && x<=137+f*64 && y>=ny-7 && y<=ny+7)
                            base_rgb=accent;
                        // 起音后数帧的局部弦振动，不让整块指板持续抖动。
                        if(note_activity(open_note(s)+f,octave,activity)>3 &&
                           x>=141+f*64 && x<181+f*64 &&
                           ((x[4] && y==ny-2) || (!x[4] && y==ny+2)))base_rgb=accent;
                    end
                end
            end
        end

        // 正文字库与48px标题复用，字库尺寸不随此布局扩大。
        text4(32,36,2,{6'd7,6'd8,12'd0},C_MUTED); // 静奏
        if(!instrument_guitar)title4(128,24,2,{6'd3,6'd4,6'd0});
        else title4(128,24,3,{6'd1,6'd5,6'd6});
        text4(788,36,2,{6'd3,6'd4,12'd0},C_TEXT);
        text4(908,36,2,{6'd5,6'd6,12'd0},C_TEXT);
        text4(32,108,2,{6'd9,6'd10,12'd0},C_MUTED);
        num4(104,108,3,{(volume<100?6'd0:dg(volume_digits[11:8])),
             (volume<10?6'd0:dg(volume_digits[7:4])),dg(volume_digits[3:0]),6'd0},C_TEXT);
        text4(220,108,2,{6'd11,6'd9,12'd0},C_MUTED);
        num4(320,108,1,{dg(bend_digits[11:8]),18'd0},C_TEXT);
        num4(356,108,2,{dg(bend_digits[7:4]),dg(bend_digits[3:0]),12'd0},C_TEXT);
        if(x>=294 && x<310 && y>=119 && y<122)base_rgb=C_TEXT;
        if(!pitch_bend[15] && x>=301 && x<304 && y>=113 && y<128)base_rgb=C_TEXT;
        if(x>=346 && x<350 && y>=128 && y<132)base_rgb=C_TEXT;
        text4(492,108,2,{6'd9,6'd16,12'd0},C_MUTED);
        text4(588,108,1,{6'd13,18'd0},C_TEXT);
        text4(652,108,1,{6'd14,18'd0},C_TEXT);
        text4(716,108,1,{6'd15,18'd0},C_TEXT);
        text4(800,108,2,{6'd17,6'd9,12'd0},C_MUTED);
        text4(872,108,1,{(sustain?6'd18:6'd19),18'd0},C_TEXT);
        // 简洁的开关指示；尚无USB控制器时只反映实际sustain状态。
        if(x>=930 && x<978 && y>=112 && y<128)base_rgb=sustain?accent:24'hb7bab6;
        if(y>=110 && y<130 &&
           ((sustain && x>=960 && x<980) || (!sustain && x>=928 && x<948)))base_rgb=24'hffffff;
        text4(48,172,4,{6'd20,6'd21,6'd22,6'd23},24'he9ebe3);
        num4(720,172,4,{6'd47,gain_glyphs},24'he9ebe3);
        text4(880,172,2,{6'd37,6'd38,12'd0},24'he9ebe3);
        if(!instrument_guitar)begin
            for(k=0;k<8;k=k+1)
                text4(66+k*120,540,2,{white_letter(k),(k==7?last_octave_glyph:first_octave_glyph),12'd0},C_TEXT);
        end else begin
            text4(40,352,2,{6'd33,6'd34,12'd0},C_MUTED); // 指位；与0品标签错开。
            for(s=0;s<6;s=s+1)
                text4(40,384+s*24,1,{dg(s[3:0]+1'b1),18'd0},C_MUTED);
            for(f=0;f<=12;f=f+1)begin
                if(octave==2)begin
                    if(f<8)num4(103+f*64,352,2,{6'd49,dg(f[3:0]+4'd2),12'd0},C_MUTED);
                    else num4(103+f*64,352,2,{6'd50,dg(f[3:0]-4'd8),12'd0},C_MUTED);
                end else if(f<10)num4(116+f*64,352,1,{dg(f[3:0]),18'd0},C_MUTED);
                else num4(103+f*64,352,2,{6'd49,dg(f[3:0]-4'd10),12'd0},C_MUTED);
            end
            for(k=0;k<13;k=k+1)begin
                text4(36+k*74,548,1,{note_letter(k),18'd0},C_TEXT);
                num4(72+k*74,548,1,{(k==12?last_octave_glyph:first_octave_glyph),18'd0},C_TEXT);
                if((k==1 || k==3 || k==6 || k==8 || k==10) &&
                   x>=62+k*74 && x<70+k*74 && y>=553 && y<566 &&
                   (y==556 || y==562 || x==64+k*74 || x==68+k*74))base_rgb=C_TEXT;
            end
        end
        // 顶部独立小区域最后选择，避免把新文字叠进整屏文字优先长链。
        // 吉他只在下方音名键提示下一音，不枚举78个等音指位标记。
        if(ENABLE_GUIDE && x>=352 && x<704 && y>=24 && y<75)begin
            text4(360,36,2,{6'd33,6'd35,12'd0},C_MUTED);
            num4(430,36,2,{dg(guide_digits[7:4]),dg(guide_digits[3:0]),12'd0},C_TEXT);
            num4(500,36,2,{6'd49,6'd52,12'd0},C_TEXT);
            // 在此坐标窗内x高位固定480、y高位固定32，只需6位局部和26/27。
            // 不能仅比较模16，否则左上端会多出一个像素。
            if(x>=483 && x<495 && y>=40 && y<58 &&
               (slash_sum==26 || slash_sum==27))base_rgb=C_MUTED;
            text4(580,36,2,{note_letter(guide_index),first_octave_glyph,12'd0},C_TEXT);
            if(x>=360 && x<696 && y>=69 && y<72)begin
                base_rgb=grid;
                if(guide_x<{3'd0,guide_width})base_rgb=24'h397e75;
            end
        end
        // Physical AIN2 fader readout. This does not imply USB dragging is connected.
        if(SHOW_BRIGHTNESS && x>=352 && x<704 && y>=24 && y<76)begin
            text4(360,28,3,{6'd58,6'd59,6'd60,6'd0},C_MUTED);
            num4(620,28,3,{(brightness<100?6'd0:dg(brightness_digits[11:8])),
                (brightness<10?6'd0:dg(brightness_digits[7:4])),dg(brightness_digits[3:0]),6'd0},C_TEXT);
            if(x>=360 && x<679 && y>=64 && y<68)begin
                base_rgb=grid;
                if(x<=brightness_position)base_rgb=accent;
            end
            if(x+4>=brightness_position && x<brightness_position+4 && y>=58 && y<74)
                base_rgb=C_TEXT;
        end
    end
endmodule
