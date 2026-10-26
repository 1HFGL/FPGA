// 1024x600“静奏·简洁版”：暖白底、淡黄反馈、真实波形和双乐器主体。
// 与 instrument_panel_renderer 的区别：
//   - 文本分两个层次：24px 正文与 48px 原生标题，不再把 24px 点阵整数放大；
//   - 字形以覆盖度 0..3 表示，由上层与背景做一次线性混合，边缘平滑；
//   - 钢琴键盘与吉他指板共用同一网格与配色体系，主体形态各自体现乐器。
// 默认组合绘制；正式入口仅在帧提交沿预存弯音数字，坐标仍为编译期常量。
// 不含除法、开方或整屏帧缓存，像素请求流水线不增加拍数。
// 文本接口：本模块在 P0 给出字形/行/列请求，字模 ROM 在 P1 返回整行覆盖度。
module panel_reference #(
    // 保留队友触摸准备版的接口兼容；当前简洁布局不叠加旧版顶部滑条。
    // USB主机尚未接通，不能把不可用的控件画成已经能操作。
    parameter integer TOUCH_PANEL=0,
    parameter integer ENABLE_GUIDE=0,
    parameter integer CONTROL_FEATURES=0,
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
    input wire [74:0] guide_status,
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
    output reg [6:0] text_glyph,
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
    wire [3:0] control_kind;
    wire [1:0] control_value;
    instrument_ui_map #(.CONTROL_WIDTH(4),.EXTENDED(CONTROL_FEATURES)) u_map(.x(x),.y(y),.instrument_guitar(instrument_guitar),
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
        input [9:0] value;
        reg [11:0] digits;
        integer b;
        begin
            digits = 0;
            for (b = 9; b >= 0; b = b - 1) begin
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
    wire [2:0] practice_state=guide_status[57:55];
    wire [7:0] practice_bpm=guide_status[54:47];
    wire [9:0] practice_progress=guide_status[46:37];
    wire [36:0] target_all=guide_status[36:0];
    wire [12:0] targets=octave==0?target_all[12:0]:octave==2?target_all[36:24]:target_all[24:12];
    reg [11:0] practice_bpm_digits,practice_progress_digits;
    // 状态变化先格式化寄存，不在像素组合路径上计算十进制。
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin practice_bpm_digits<=0;practice_progress_digits<=0;end
        else begin
            practice_bpm_digits<=decimal_digits({1'b0,practice_bpm});
            practice_progress_digits<=decimal_digits(practice_progress);
        end
    end
    // 新字模7位编号；保持原text4/num4及旧字形位置不变。
    task caption;
        input [11:0] left,top;
        input [27:0] ids;
        reg [11:0] lx,ly;
        begin
            lx=x-left;ly=y-top;
            if(x>=left && y>=top && lx<104 && ly<24)begin
                if(lx>=78)begin text_glyph=ids[6:0];lx=lx-12'd78;end
                else if(lx>=52)begin text_glyph=ids[13:7];lx=lx-12'd52;end
                else if(lx>=26)begin text_glyph=ids[20:14];lx=lx-12'd26;end
                else text_glyph=ids[27:21];
                if(lx<24 && text_glyph!=0)begin
                    text_enable=1;text_column=lx[4:0];text_row=ly[4:0];text_color=24'he9ebe3;
                end
            end
        end
    endtask
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
        if(!CONTROL_FEATURES && x>=904 && x<936 && y>=208 && y<336)begin
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
            if(((CONTROL_FEATURES && targets[key_index]) || (ENABLE_GUIDE && guide_valid && key_index==guide_index)) &&
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

        // 标题沿用原字模；练习正文扩至7位编号，原字形不改。
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
        // 开关只显示已经接受的真实延音状态。
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

        if(CONTROL_FEATURES)begin
            // 水平电平条与两个练习控件共用右侧区域，不覆盖真实波形。
            if(x>=864 && x<992 && y>=208 && y<228)begin
                base_rgb=24'h424a4c;
                if(x-864<{4'd0,level_height})base_rgb=peak_level>30000?24'he18b77:accent;
                if(held_peak_height!=0 && x-864=={4'd0,held_peak_height})base_rgb=24'hf7f7ed;
            end
            if(control_kind==4 || control_kind==5 || control_kind==7 || control_kind==9)
                base_rgb=24'h424a4c;
            // 目标所在音区以短线提示；边界C允许相邻两档，休止时全灭。
            if(y>=138 && y<141 && ((x>=588 && x<612 && |target_all[12:0]) ||
               (x>=652 && x<676 && |target_all[24:12]) || (x>=716 && x<740 && |target_all[36:24])))base_rgb=24'h397e75;
            caption(880,228,practice_state==1?{7'd82,7'd83,14'd0}:practice_state==4?{7'd80,7'd81,14'd0}:28'd0);
            caption(484,170,{7'd79,21'd0});
            caption(200,170,guide_status[62]?{7'd69,7'd67,7'd68,7'd0}:guide_status[60]?{7'd67,7'd68,7'd66,7'd0}:{7'd64,7'd65,7'd66,7'd0});
            caption(880,260,practice_state==3?{7'd74,7'd75,7'd0,7'd0}:(practice_state==1 || practice_state==2)?{7'd72,7'd73,7'd0,7'd0}:{7'd70,7'd71,7'd0,7'd0});
            caption(880,308,{7'd76,7'd77,7'd0,7'd0});
            num4(392,170,3,{dg(practice_progress_digits[11:8]),dg(practice_progress_digits[7:4]),dg(practice_progress_digits[3:0]),6'd0},24'he9ebe3);
            num4(516,170,3,{dg(practice_bpm_digits[11:8]),dg(practice_bpm_digits[7:4]),dg(practice_bpm_digits[3:0]),6'd0},24'he9ebe3);
            if(y>=179 && y<182 && ((x>=626 && x<646)||(x>=674 && x<694)))base_rgb=24'he9ebe3;
            if(x>=682 && x<685 && y>=172 && y<189)base_rgb=24'he9ebe3;
            // 四拍点；预备与演奏沿用相同拍相，目标框不代表实际持键。
            for(k=0;k<4;k=k+1)
                if(x>=336+k*12 && x<344+k*12 && y>=174 && y<182)
                    base_rgb=(guide_status[59:58]==k && (practice_state==1 || practice_state==2))?accent:24'h626963;
        end
    end
endmodule

// B部分通用显示入口：800x480 基础界面与 1024x600 正式界面。
// sys_* 输入均同步于 sys_clk；pixel_clk 单独输入，禁止把未同步数据直接接渲染器。
// rst_n 是两显示时钟域共同复位，板级应合并外部复位和像素PLL失锁；各域内部同步释放。
// 本模块不生成PLL、不分配封装脚、不驱动背光供电，不是可直接下载的板级顶层。
//
// 像素流水线（每级都在 pixel_clk 上寄存，DE/HS/VS 与数据同延迟）：
//   S0  x/y 由时序发生器给出；波形 RAM 在本拍读地址，下一拍返回数据。
//   S1  x_d/y_d = x/y；渲染器按 x_d/y_d 组合绘制，同时向字模请求字形行。
//   S2  base_l1 锁存渲染底色；字模 ROM 输出整行覆盖度；列号锁存。
//   S3  base_l2 + 覆盖度混合成最终 RGB，与 de_l2 同拍输出。
// 覆盖度 0 表示背景；1/2 用于半覆盖；3 与文字色完全相同，便于逐像素核对。
module instrument_display_reference #(
    parameter integer H_ACTIVE=800, V_ACTIVE=480,
    parameter integer UI_X=0, UI_Y=0, // 逻辑界面在有效区中的左上角
    parameter integer WIDE=0, // 0:800x480，1:1024x600原生布局
    parameter integer H_FRONT=40, H_SYNC=128, H_BACK=88,
    parameter integer V_FRONT=13, V_SYNC=2, V_BACK=30,
    parameter integer HS_ACTIVE=0, VS_ACTIVE=0,
    parameter integer WAVE_GAIN_SHIFT=3, // 通用入口固定倍率
    parameter integer ENHANCED=0, // 正式1024x600：双乐器主体、16位峰值波形
    parameter integer TOUCH_PANEL=0, // prepared normalized touch brightness UI
    parameter integer UI=0, // 1：2bit覆盖度字模新版界面；0：保留旧逐像素测试路径
    parameter integer ENABLE_GUIDE=0,
    parameter integer CONTROL_FEATURES=0,
    parameter integer BRIGHTNESS_PANEL=0
) (
    input wire sys_clk, pixel_clk, rst_n,
    input wire [12:0] key_down, // 当前档位的C,C#,D,...,B,C
    input wire [12:0] piano_keys,guitar_keys, // 已分配且仍持有的分音色音符
    input wire [6:0] volume, // 0..127
    input wire signed [15:0] pitch_bend, // 显示归一化码：-32768..32767 对应 -2..+2半音
    input wire [1:0] octave, // 0低/1中/2高；3显示为中档
    input wire sustain, instrument_guitar, // 音色状态：0钢琴，1吉他；不是切换命令
    input wire [6:0] brightness,
    input wire touch_available,
    input wire audio_valid,
    input wire signed [15:0] audio_sample, // 最终混音后的样本副本，每次valid代表一个样本
    output reg [23:0] lcd_rgb,
    output reg lcd_de, lcd_hsync, lcd_vsync,
    output reg frame_start, // 与输出RGB/DE同拍，像素域单周期脉冲
    output wire display_sample_drop, // sys_clk域，信箱忙时丢失显示样本；绝不反压音频
    input wire [74:0] guide_status,
    input wire guide_valid,
    input wire [3:0] guide_index,guide_progress
);
    reg [1:0] sys_release, pixel_release;
    always @(posedge sys_clk or negedge rst_n)
        if (!rst_n) sys_release<=0;
        else sys_release<={sys_release[0],1'b1};
    always @(posedge pixel_clk or negedge rst_n)
        if (!rst_n) pixel_release<=0;
        else pixel_release<={pixel_release[0],1'b1};
    wire sys_rst_n=sys_release[1], pixel_rst_n=pixel_release[1];
    wire [157:0] state_latest;
    reg [157:0] state_frame;
    wire [15:0] sample_pixel;
    wire sample_pixel_valid, sample_ready;
    // 状态与音频副本各走一条单格信箱；显示等待绝不反馈到音频域。
    display_cdc_latest #(.WIDTH(158)) u_status (
        .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_valid(1'b1),
        .src_data({(CONTROL_FEATURES?guide_status:75'd0),(ENABLE_GUIDE?guide_valid:1'b0),(ENABLE_GUIDE?guide_index:4'd0),(ENABLE_GUIDE?guide_progress:4'd0),
                   (TOUCH_PANEL?touch_available:1'b0),(TOUCH_PANEL?brightness:7'd127),
                   (ENHANCED?guitar_keys:13'd0),(ENHANCED?piano_keys:13'd0),
                   instrument_guitar,sustain,octave,pitch_bend,volume,key_down}),.src_ready(),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_valid(),.dst_data(state_latest));
    display_cdc_latest #(.WIDTH(16)) u_sample (
        .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_valid(audio_valid),
        .src_data(audio_sample),.src_ready(sample_ready),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),
        .dst_valid(sample_pixel_valid),.dst_data(sample_pixel));
    assign display_sample_drop=sys_rst_n && audio_valid && !sample_ready;

    wire [11:0] scan_x,scan_y;
    localparam integer UI_WIDTH=WIDE?1024:800, UI_HEIGHT=WIDE?600:480;
    localparam [11:0] WAVE_X=WIDE?12'd256:12'd144;
    wire in_ui=(scan_x>=UI_X && scan_x<UI_X+UI_WIDTH && scan_y>=UI_Y && scan_y<UI_Y+UI_HEIGHT);
    wire [11:0] x=scan_x-UI_X[11:0], y=scan_y-UI_Y[11:0];
    wire de,hs,vs,start,commit;
    lcd_rgb_timing #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE),.H_FRONT(H_FRONT),.H_SYNC(H_SYNC),.H_BACK(H_BACK),
        .V_FRONT(V_FRONT),.V_SYNC(V_SYNC),.V_BACK(V_BACK),
        .HS_ACTIVE(HS_ACTIVE),.VS_ACTIVE(VS_ACTIVE)) u_timing (
        .pixel_clk(pixel_clk),.rst_n(pixel_rst_n),.x(scan_x),.y(scan_y),
        .de(de),.hsync(hs),.vsync(vs),.frame_start(start),.frame_commit(commit));

    // ---- 基础入口（ENHANCED=0）：256 点单线波形 + 1bit 字库 ----
    // 先符号扩展再放大；饱和后取高8位，禁止大信号溢出翻转波形。
    wire signed [31:0] expanded={{16{sample_pixel[15]}},sample_pixel};
    wire signed [31:0] amplified=expanded <<< WAVE_GAIN_SHIFT;
    wire [7:0] sample8=(amplified>32'sd32767) ? 8'h7f :
                       (amplified< -32'sd32768) ? 8'h80 : amplified[15:8];
    wire [11:0] wave_offset=x-WAVE_X;
    wire [7:0] wave_address=(x>=WAVE_X && x<WAVE_X+12'd512) ? wave_offset[8:1] : 8'd0;
    wire [7:0] wave_data;
    wire wave_ready;
    display_wave_buffer u_wave (
        .pixel_clk(pixel_clk),.rst_n(pixel_rst_n),.sample_valid(sample_pixel_valid),
        .sample_data(sample8),.frame_commit(commit),.read_addr(wave_address),
        .read_data(wave_data),.wave_ready(wave_ready));

    // 每列 3 像素的地址计数，避免在 49MHz 像素路径上计算 x/3。
    reg [7:0] envelope_address;
    reg [1:0] envelope_repeat;
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin envelope_address<=0;envelope_repeat<=0;end
        else if(x<48 || x>=816)begin envelope_address<=0;envelope_repeat<=0;end
        else if(envelope_repeat==2)begin envelope_address<=envelope_address+1'b1;envelope_repeat<=0;end
        else envelope_repeat<=envelope_repeat+1'b1;
    end
    wire signed [15:0] envelope_min,envelope_max;
    wire [15:0] envelope_peak;
    wire [3:0] envelope_gain;
    wire envelope_ready;
    generate if(ENHANCED)begin:g_envelope
        display_wave_envelope u_capture(.pixel_clk(pixel_clk),.rst_n(pixel_rst_n),
            .sample_valid(sample_pixel_valid),.sample_data(sample_pixel),.frame_commit(commit),
            .read_addr(envelope_address),.read_min(envelope_min),.read_max(envelope_max),
            .peak_level(envelope_peak),.gain_shift(envelope_gain),.wave_ready(envelope_ready));
    end else begin:g_simple_wave
        assign envelope_min=0;assign envelope_max=0;assign envelope_peak=0;
        assign envelope_gain=0;assign envelope_ready=0;
    end endgenerate

    // ---- S1：坐标延迟一拍，与波形 RAM 的一拍读延迟对齐 ----
    reg [11:0] x_d,y_d;
    reg de_d,hs_d,vs_d,start_d,wave_ready_d,ui_d;
    wire [23:0] pixel_base,text_color;
    wire [6:0] text_glyph;
    wire [5:0] legacy_text_glyph;
    wire [4:0] text_column,text_row;
    wire text_enable;
    wire title_enable;
    wire [2:0] title_glyph;
    wire [5:0] title_column,title_row;
    wire [38:0] activity;
    wire [15:0] meter_level,meter_peak;
    wire [7:0] meter_height,meter_peak_height;
    generate if(ENHANCED && UI)begin:g_feedback
        display_feedback u_feedback(.pixel_clk(pixel_clk),.rst_n(pixel_rst_n),.frame_commit(commit),
            .held(state_latest[39]?state_latest[65:53]:state_latest[52:40]),
            .instrument_guitar(state_latest[39]),.raw_peak(envelope_peak),
            .activity(activity),.meter_level(meter_level),.meter_peak(meter_peak),
            .meter_height(meter_height),.meter_peak_height(meter_peak_height));
    end else begin:g_no_feedback
        assign activity=0;assign meter_level=0;assign meter_peak=0;
        assign meter_height=0;assign meter_peak_height=0;
    end endgenerate
    generate if(ENHANCED && UI)begin:g_panel
        panel_reference #(.CONTROL_FEATURES(CONTROL_FEATURES),.TOUCH_PANEL(TOUCH_PANEL),.ENABLE_GUIDE(ENABLE_GUIDE),
            .LOG_METER(1),.SHOW_BRIGHTNESS(BRIGHTNESS_PANEL),.FRAME_BEND(1)) u_renderer(
            // 与state_frame同沿读取state_latest，数字和符号不会错开一帧。
            .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.frame_commit(commit),
            .pitch_bend_latest(state_latest[35:20]),
            .guide_status(state_frame[157:83]),.guide_valid(state_frame[82]),.guide_index(state_frame[81:78]),.guide_progress(state_frame[77:74]),
            .brightness(state_frame[72:66]),.touch_available(state_frame[73]),
            .x(x_d),.y(y_d),.key_down(state_frame[39]?state_frame[65:53]:state_frame[52:40]),
            .volume(state_frame[19:13]),.pitch_bend(state_frame[35:20]),.octave(state_frame[37:36]),
            .sustain(state_frame[38]),.instrument_guitar(state_frame[39]),
            .wave_min(envelope_min),.wave_max(envelope_max),.peak_level(envelope_peak),
            .gain_shift(envelope_gain),.wave_ready(wave_ready_d),
            .activity(activity),.meter_level(meter_level),.meter_peak(meter_peak),
            .meter_height(meter_height),.meter_peak_height(meter_peak_height),
            .text_enable(text_enable),.text_glyph(text_glyph),
            .text_column(text_column),.text_row(text_row),.text_color(text_color),
            .title_enable(title_enable),.title_glyph(title_glyph),
            .title_column(title_column),.title_row(title_row),.base_rgb(pixel_base));
    end else if(ENHANCED)begin:g_enhanced_panel
        // 旧 1024x600 绘制器：保留给既有逐像素帧测试，布局与颜色常量不变。
        assign text_glyph={1'b0,legacy_text_glyph};
        instrument_panel_renderer u_renderer_legacy(
            .x(x_d),.y(y_d),.key_down(state_frame[39]?state_frame[65:53]:state_frame[52:40]),
            .volume(state_frame[19:13]),.pitch_bend(state_frame[35:20]),.octave(state_frame[37:36]),
            .sustain(state_frame[38]),.instrument_guitar(state_frame[39]),
            .wave_min(envelope_min),.wave_max(envelope_max),.peak_level(envelope_peak),
            .gain_shift(envelope_gain),.wave_ready(wave_ready_d),.base_rgb(pixel_base),
            .text_glyph(legacy_text_glyph),.text_column(text_column),.text_row(text_row),
            .text_enable(text_enable),.text_color(text_color));
        assign title_enable=1'b0;
        assign title_glyph=0;
        assign title_column=0;
        assign title_row=0;
    end else begin:g_simple_panel
        assign text_glyph={1'b0,legacy_text_glyph};
        piano_display_renderer #(.WIDE(WIDE)) u_renderer (
            .x(x_d),.y(y_d),.key_down(state_frame[12:0]),.volume(state_frame[19:13]),
            .pitch_bend(state_frame[35:20]),.octave(state_frame[37:36]),
            .sustain(state_frame[38]),.instrument_guitar(state_frame[39]),
            .wave_data(wave_data),.wave_ready(wave_ready_d),.rgb(),.base_rgb(pixel_base),
            .text_glyph(legacy_text_glyph),.text_column(text_column),.text_row(text_row),
            .text_enable(text_enable),.text_color(text_color));
        assign title_enable=1'b0;
        assign title_glyph=0;
        assign title_column=0;
        assign title_row=0;
    end endgenerate

    // ---- S2：字模 ROM 打出整行覆盖度；列号同拍锁存 ----
    wire [47:0] text_bits;
    wire [95:0] title_bits;
    reg [47:0] text_bits_q;
    reg [95:0] title_bits_q;
    reg [23:0] base_l1,color_l1;
    reg [4:0] text_col_q;
    reg [5:0] title_col_q;
    reg text_on_q,title_on_q;
    reg de_l1,hs_l1,vs_l1,start_l1,ui_l1;
    wire font_ink;
    generate if(ENHANCED && UI)begin:g_ui_font
        display_font_ui u_font(.pixel_clk(pixel_clk),
            .text_glyph(text_glyph),.text_row(text_row),.text_bits(text_bits),
            .title_glyph(title_glyph),.title_row(title_row),.title_bits(title_bits));
    end else begin:g_legacy_font
        display_font24 #(.SYNCHRONOUS(1),.EXTENDED(0)) u_font(.pixel_clk(pixel_clk),
            .glyph_id(text_glyph[5:0]),.column(text_column),.row(text_row),.ink(font_ink));
    end endgenerate

    // 覆盖度选择：行数据与列号都在 S2 末尾有效。
    // 字模行按“左侧像素在高位”打包：第 c 列占 bit[W-1-2c : W-2-2c]。
    // 因此下标要从行宽倒着数，不能直接用 2c 取低段。
    // 下标为 47-2c（文本）和 95-2c（标题）。先把 2c 明确截到目标位宽，
    // 再做同宽减法，避免综合器把中间结果扩宽后报截断。
    wire [5:0] text_double={text_col_q[4:0],1'b0};
    wire [6:0] title_double={title_col_q[5:0],1'b0};
    wire [5:0] text_bit_index=6'd47-text_double;
    wire [6:0] title_bit_index=7'd95-title_double;
    wire [1:0] text_cov=text_bits[text_bit_index -: 2];
    wire [1:0] title_cov=title_bits[title_bit_index -: 2];
    wire [1:0] cov = (ENHANCED && UI) ? (title_on_q ? title_cov : text_cov) : (font_ink ? 2'd3 : 2'd0);
    // 覆盖度混合：cov=0 纯背景，1→5/8，2→7/8，3→文字色。
    // 24px 中文的笔画大量落在半覆盖上，若按 1/4、1/2 线性混合会显得发灰发虚；
    // 这里把两级覆盖度推近文字色，只保留轻微抗锯齿。
    // 每通道只用“差值右移 + 加减”，差值与步长显式定为 9 位有符号，避免 32 位隐式截断。
    wire [23:0] ink = color_l1;
    wire signed [8:0] dr = $signed({1'b0,ink[23:16]})- $signed({1'b0,base_l1[23:16]});
    wire signed [8:0] dg = $signed({1'b0,ink[15:8]}) - $signed({1'b0,base_l1[15:8]});
    wire signed [8:0] db = $signed({1'b0,ink[7:0]})  - $signed({1'b0,base_l1[7:0]});
    wire signed [8:0] sr = dr >>> 3; // 1/8 步长
    wire signed [8:0] sg = dg >>> 3;
    wire signed [8:0] sb = db >>> 3;
    wire signed [8:0] near_r = $signed({1'b0,ink[23:16]}) - sr; // 7/8
    wire signed [8:0] near_g = $signed({1'b0,ink[15:8]})  - sg;
    wire signed [8:0] near_b = $signed({1'b0,ink[7:0]})   - sb;
    wire signed [8:0] mid_r = $signed({1'b0,base_l1[23:16]}) + (sr <<< 2) + sr; // 5/8
    wire signed [8:0] mid_g = $signed({1'b0,base_l1[15:8]})  + (sg <<< 2) + sg;
    wire signed [8:0] mid_b = $signed({1'b0,base_l1[7:0]})   + (sb <<< 2) + sb;
    wire [7:0] mix_r = (cov==2'd3) ? ink[23:16] :
                       (cov==2'd2) ? near_r[7:0] :
                       (cov==2'd1) ? mid_r[7:0]  : base_l1[23:16];
    wire [7:0] mix_g = (cov==2'd3) ? ink[15:8] :
                       (cov==2'd2) ? near_g[7:0] :
                       (cov==2'd1) ? mid_g[7:0]  : base_l1[15:8];
    wire [7:0] mix_b = (cov==2'd3) ? ink[7:0] :
                       (cov==2'd2) ? near_b[7:0] :
                       (cov==2'd1) ? mid_b[7:0]  : base_l1[7:0];

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            state_frame<={9'd0,1'b0,7'd127,66'd0};
            x_d<=0; y_d<=0; de_d<=0; start_d<=0; wave_ready_d<=0; ui_d<=0;
            hs_d<=(HS_ACTIVE==0); vs_d<=(VS_ACTIVE==0);
            base_l1<=0;color_l1<=0;
            text_bits_q<=0;title_bits_q<=0;text_col_q<=0;title_col_q<=0;
            text_on_q<=0;title_on_q<=0;
            de_l1<=0;hs_l1<=(HS_ACTIVE==0);vs_l1<=(VS_ACTIVE==0);start_l1<=0;ui_l1<=0;
            lcd_rgb<=0; lcd_de<=0; lcd_hsync<=(HS_ACTIVE==0); lcd_vsync<=(VS_ACTIVE==0);
            frame_start<=0;
        end else begin
            if (commit) state_frame<=state_latest;
            // S0 -> S1：坐标与行场同步一起延迟，保证边界不错位。
            x_d<=x; y_d<=y;
            de_d<=de; hs_d<=hs; vs_d<=vs; start_d<=start; ui_d<=in_ui;
            wave_ready_d<=ENHANCED?envelope_ready:wave_ready;

            // S1 -> S2：底色/文字色/列号/请求有效位。
            base_l1<=pixel_base; color_l1<=text_color;
            text_bits_q<=text_bits; title_bits_q<=title_bits;
            text_col_q<=text_column[4:0]; title_col_q<=title_column[5:0];
            text_on_q<=text_enable; title_on_q<=title_enable;
            de_l1<=de_d; hs_l1<=hs_d; vs_l1<=vs_d; start_l1<=start_d; ui_l1<=ui_d;

            // S2 -> 输出：mix 读 S2 寄存器，DE/HS/VS 与之同拍寄存。
            lcd_rgb <= de_l1 && ui_l1 ? (cov ? {mix_r,mix_g,mix_b} : base_l1) : 24'd0;
            lcd_de<=de_l1; lcd_hsync<=hs_l1; lcd_vsync<=vs_l1; frame_start<=start_l1;
        end
    end
endmodule

`timescale 1ns/1ps
// 对照固定Git原版，逐拍比较真实RGB、同步、帧快照及显示丢样；不修改既有TB。
module tb_pipeline_display_equivalence;
    reg clk=0,pclk=0,run_pixel=1,rst_n=0;
    reg [6:0] volume=96,brightness=64;
    reg signed [15:0] bend=-16384;
    reg guitar=0,sustain=0;
    reg [74:0] guide={17'd0,3'd2,8'd90,10'd0,37'h1000};
    reg [1:0] octave=1;
    reg [12:0] keys=13'h091;
    reg valid=0;
    reg [10:0] divider=0;
    reg signed [15:0] sample=0;
    always #10 clk=~clk;
    always #10.204082 if(run_pixel)pclk=~pclk;
    always @(posedge clk)begin
        valid<=0;
        if(divider==1041)begin
            divider<=0;valid<=1;sample<=sample+16'sd211;
        end else divider<=divider+1'b1;
    end
    wire [23:0] rgb,old_rgb;
    wire de,hs,vs,fs,drop,old_de,old_hs,old_vs,old_fs,old_drop;
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),.CONTROL_FEATURES(1),
        .TOUCH_PANEL(1),.BRIGHTNESS_PANEL(1),.H_FRONT(40),.H_SYNC(104),.H_BACK(144),
        .V_FRONT(3),.V_SYNC(7),.V_BACK(14)) dut(
        .sys_clk(clk),.pixel_clk(pclk),.rst_n(rst_n),.key_down(keys),
        .piano_keys(guitar?13'd0:keys),.guitar_keys(guitar?keys:13'd0),
        .volume(volume),.pitch_bend(bend),.octave(octave),.sustain(sustain),
        .instrument_guitar(guitar),.brightness(brightness),.touch_available(1'b1),
        .guide_status(guide),.guide_valid(1'b0),.guide_index(4'd0),.guide_progress(4'd0),
        .audio_valid(valid),.audio_sample(sample),.lcd_rgb(rgb),.lcd_de(de),
        .lcd_hsync(hs),.lcd_vsync(vs),.frame_start(fs),.display_sample_drop(drop));
    instrument_display_reference #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),.CONTROL_FEATURES(1),
        .TOUCH_PANEL(1),.BRIGHTNESS_PANEL(1),.H_FRONT(40),.H_SYNC(104),.H_BACK(144),
        .V_FRONT(3),.V_SYNC(7),.V_BACK(14)) reference(
        .sys_clk(clk),.pixel_clk(pclk),.rst_n(rst_n),.key_down(keys),
        .piano_keys(guitar?13'd0:keys),.guitar_keys(guitar?keys:13'd0),
        .volume(volume),.pitch_bend(bend),.octave(octave),.sustain(sustain),
        .instrument_guitar(guitar),.brightness(brightness),.touch_available(1'b1),
        .guide_status(guide),.guide_valid(1'b0),.guide_index(4'd0),.guide_progress(4'd0),
        .audio_valid(valid),.audio_sample(sample),.lcd_rgb(old_rgb),.lcd_de(old_de),
        .lcd_hsync(old_hs),.lcd_vsync(old_vs),.frame_start(old_fs),.display_sample_drop(old_drop));
    integer cycles=0,commits=0,piano_pixels=0,guitar_pixels=0;
    always @(posedge pclk)begin
        if(dut.pixel_rst_n && dut.commit)commits=commits+1;
        #1;
        if(rst_n)begin
            cycles=cycles+1;
            if({rgb,de,hs,vs,fs,drop}!=={old_rgb,old_de,old_hs,old_vs,old_fs,old_drop})begin
                $display("FAIL display pixel/sync cycle=%0d new=%h old=%h",cycles,rgb,old_rgb);$stop;
            end
            if(dut.state_frame!==reference.state_frame ||
               dut.g_panel.u_renderer.bend_digits!==reference.g_panel.u_renderer.bend_digits)begin
                $display("FAIL display frame digits cycle=%0d commits=%0d new=%h old=%h",cycles,commits,
                         dut.g_panel.u_renderer.bend_digits,reference.g_panel.u_renderer.bend_digits);$stop;
            end
            if(de)begin
                if(dut.state_frame[39])guitar_pixels=guitar_pixels+1;
                else piano_pixels=piano_pixels+1;
            end
        end
    end
    initial begin
        #1;rst_n=1;#1;rst_n=0;
        repeat(8)@(negedge clk);rst_n=1;
        wait(commits==1);
        @(negedge clk);guitar=1;bend=16'sh8000;volume=127;brightness=1;octave=2;keys=13'h1555;sustain=1;guide={17'd0,3'd3,8'd240,10'd511,37'h1555555555};
        wait(commits==2);
        @(negedge clk);bend=16'sh7fff;volume=1;brightness=127;octave=0;keys=13'h0222;guide={17'd0,3'd4,8'd30,10'd512,37'h15555};
        wait(commits==3);repeat(8)@(negedge pclk);
        if(piano_pixels<614400 || guitar_pixels<614400)begin
            $display("FAIL display coverage piano=%0d guitar=%0d",piano_pixels,guitar_pixels);$stop;
        end
        @(negedge pclk);run_pixel=0;#3;rst_n=0;#1;
        if(rgb!==0 || de!==0 || dut.g_panel.u_renderer.bend_digits!==0)begin
            $display("FAIL display stopped-clock reset");$stop;
        end
        #100;run_pixel=1;repeat(8)@(negedge clk);rst_n=1;repeat(100)@(negedge pclk);
        $display("PASS tb_pipeline_display_equivalence: cycles=%0d piano_pixels=%0d guitar_pixels=%0d; RGB/sync/CDC/format frame-atomic, clock-stop reset/restart",cycles,piano_pixels,guitar_pixels);
        $finish;
    end
    initial begin #60000000;$display("FAIL display equivalence timeout");$stop;end
endmodule
