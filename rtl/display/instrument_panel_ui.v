// 1024x600“静奏”绘制器：2bit 覆盖度字模 + 统一参数卡 + 乐器主体。
// 与 instrument_panel_renderer 的区别：
//   - 文本分两个层次：24px 正文与 48px 原生标题，不再把 24px 点阵整数放大；
//   - 字形以覆盖度 0..3 表示，由上层与背景做一次线性混合，边缘平滑；
//   - 钢琴键盘与吉他指板共用同一网格与配色体系，主体形态各自体现乐器。
// 本模块只做组合绘制，坐标均为编译期常量；不含除法、开方或整屏帧缓存。
// 文本接口：本模块在 P0 给出字形/行/列请求，字模 ROM 在 P1 返回整行覆盖度。
module instrument_panel_ui #(
    parameter [23:0] C_BG      = 24'h0b1116,
    parameter [23:0] C_PANEL   = 24'h141d24,
    parameter [23:0] C_GRID    = 24'h26343d,
    parameter [23:0] C_TEXT    = 24'he8eef2,
    parameter [23:0] C_MUTED   = 24'h8ea0ac,
    parameter [23:0] C_ACCENT  = 24'h65d9ed, // 钢琴：冷青
    parameter [23:0] C_WARM    = 24'hf0b76b  // 吉他：暖琥珀
) (
    input wire [11:0] x, y,
    input wire [12:0] key_down,
    input wire [6:0] volume,
    input wire signed [15:0] pitch_bend,
    input wire [1:0] octave,
    input wire sustain, instrument_guitar,
    input wire wave_ready,
    input wire signed [15:0] wave_min, wave_max,
    input wire [15:0] peak_level,
    input wire [3:0] gain_shift,
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
    output reg [23:0] base_rgb
);
    // 配色随音色切换；两套界面共用同一布局网格。
    wire [23:0] accent = instrument_guitar ? C_WARM : C_ACCENT;
    wire [23:0] bg     = instrument_guitar ? 24'h140f0b : C_BG;
    wire [23:0] panel  = instrument_guitar ? 24'h211a14 : C_PANEL;
    wire [23:0] grid   = instrument_guitar ? 24'h453427 : C_GRID;

    // ---- 波形几何：512 列 min/max，纵向约 128 像素，中轴 y=276 ----
    wire signed [31:0] low_amp  = $signed({{16{wave_min[15]}}, wave_min}) <<< gain_shift;
    wire signed [31:0] high_amp = $signed({{16{wave_max[15]}}, wave_max}) <<< gain_shift;
    wire signed [31:0] low_shifted  = low_amp  >>> 9;
    wire signed [31:0] high_shifted = high_amp >>> 9;
    // 超过满幅显示时饱和到 ±64 步，避免 12 位坐标回绕。
    wire signed [17:0] low_step  = (low_amp  >  32767) ?  18'sd63 :
                                   (low_amp  < -32768) ? -18'sd63 : low_shifted[17:0];
    wire signed [17:0] high_step = (high_amp >  32767) ?  18'sd63 :
                                   (high_amp < -32768) ? -18'sd63 : high_shifted[17:0];
    wire [11:0] wave_top    = 12'sd276 - high_step[11:0];
    wire [11:0] wave_bottom = 12'sd276 - low_step[11:0];
    wire [7:0]  level_height = peak_level[15:8]; // 0..128，未经显示放大的数字峰值

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
    wire [15:0] bend_abs = pitch_bend[15] ? (~pitch_bend + 16'd1) : pitch_bend;
    wire [23:0] bend_wide = {8'd0, bend_abs};
    wire [23:0] bend_scaled = (bend_wide << 7) + (bend_wide << 6) + (bend_wide << 3) + 24'd16384;
    wire [7:0]  bend_cents = bend_scaled[22:15];

    wire [11:0] volume_digits = decimal_digits({2'd0, volume});
    wire [11:0] bend_digits   = decimal_digits({1'b0, bend_cents});
    wire [8:0]  multiplier    = 9'd1 << gain_shift;
    wire [11:0] gain_digits   = decimal_digits(multiplier);

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

    integer k, s, f, ny;

    always @(*) begin
        // 默认值覆盖全部输出，区域外不保留上一像素（避免锁存器）。
        base_rgb = bg;
        text_enable = 1'b0;
        text_glyph = 0;
        text_column = 0;
        text_row = 0;
        text_color = C_TEXT;
        title_enable = 1'b0;
        title_glyph = 0;
        title_column = 0;
        title_row = 0;

        // ---- 顶部：标题栏与发丝线 ----
        if (y >= 74 && y < 76 && x >= 32 && x < 992) base_rgb = grid;

        // ---- 三块参数卡：32..336 / 352..704 / 720..992，y=88..184 ----
        if (y >= 88 && y < 184 && x >= 32  && x < 336) base_rgb = panel;
        if (y >= 88 && y < 184 && x >= 352 && x < 704) base_rgb = panel;
        if (y >= 88 && y < 184 && x >= 720 && x < 992) base_rgb = panel;

        // ---- 波形卡：32..992，y=192..376 ----
        if (y >= 192 && y < 376 && x >= 32 && x < 992) base_rgb = panel;
        if (y >= 208 && y < 352 && x >= 48 && x < 816) begin
            if (y == 276 || x[6:0] == 0) base_rgb = grid;      // 中轴与整列刻度
            if (wave_ready && y >= wave_top && y <= wave_bottom) base_rgb = accent;
        end
        // 右侧电平柱：真实数字峰值，红色仅表示接近满幅。
        if (y >= 208 && y < 344 && x >= 872 && x < 904) begin
            base_rgb = grid;
            if (y >= 344 - level_height) base_rgb = (peak_level > 16'd30000) ? 24'hf17e72 : accent;
        end

        // ---- 音量条：48..304，y=152..158 ----
        if (y >= 152 && y < 158 && x >= 48 && x < 304) begin
            base_rgb = grid;
            if (x < 48 + {volume, 1'b0}) base_rgb = accent;
        end
        // ---- 弯音：384..672，中线 528，±2 半音 ----
        if (y >= 152 && y < 158 && x >= 384 && x < 672) base_rgb = grid;
        if (y >= 146 && y < 164 && x >= 527 && x < 530) base_rgb = C_MUTED;
        if (y >= 148 && y < 162 &&
            x >= 400 + {~pitch_bend[15], pitch_bend[14:8]} &&
            x <  410 + {~pitch_bend[15], pitch_bend[14:8]}) base_rgb = accent;

        // ---- 乐器主体：钢琴键盘 / 吉他指板，同一底座 ----
        if (y >= 388 && y < 584 && x >= 24 && x < 1000) base_rgb = 24'h070a0d;

        if (!instrument_guitar) begin
            // 白键：32..(32+8*120)，y=400..568；键缝 1 像素，底边色条表达持键。
            for (k = 0; k < 8; k = k + 1) begin
                if (x >= 32 + k * 120 && x < 152 + k * 120 && y >= 400 && y < 568) begin
                    base_rgb = key_down[white_note(k)] ? 24'ha7e3ec : 24'heceff1;
                    if (x == 32 + k * 120 || y == 400) base_rgb = grid;
                    if (y >= 558) base_rgb = key_down[white_note(k)] ? accent : 24'hc4ccd0;
                end
            end
            // 黑键：宽 72、高 100，压在相邻白键缝上。
            for (k = 0; k < 5; k = k + 1) begin
                if (x >= 32 + black_boundary(k) * 120 - 36 &&
                    x <  32 + black_boundary(k) * 120 + 36 &&
                    y >= 400 && y < 500) begin
                    base_rgb = key_down[black_note(k)] ? accent : 24'h0a1018;
                    if (y < 404) base_rgb = 24'h39424c; // 顶部受光
                end
            end
        end else begin
            // 指板：96..928，六弦每 24 像素；0..12 品，品丝每 64 像素。
            if (x >= 96 && x < 928 && y >= 404 && y < 550) base_rgb = 24'h33251c;
            // 琴枕：指板左端加宽，区分“0 品”与普通品丝。
            if (x >= 96 && x < 102 && y >= 404 && y < 550) base_rgb = 24'hb9ad97;
            for (f = 0; f <= 13; f = f + 1)
                if (x >= 96 + f * 64 && x < 98 + f * 64 && y >= 404 && y < 550)
                    base_rgb = 24'h7d6753;
            // 品记：3/5/7/9 单点，12 品双点（画在中央两弦之间）。
            if (y >= 470 && y < 478 && x >= 96 && x < 928) begin
                for (f = 0; f <= 12; f = f + 1) begin
                    if ((f == 3 || f == 5 || f == 7 || f == 9) &&
                        x >= 128 + f * 64 - 27 && x < 128 + f * 64 - 15)
                        base_rgb = 24'h8a735d;
                    if (f == 12 && ((x >= 128 + 12 * 64 - 27 && x < 128 + 12 * 64 - 15) ||
                                    (x >= 128 + 12 * 64 - 7  && x < 128 + 12 * 64 + 5)))
                        base_rgb = 24'h8a735d;
                end
            end
            for (s = 0; s < 6; s = s + 1) begin
                ny = 416 + s * 24;
                // 弦径随音高收细：低音弦 2 像素，高音弦 1 像素。
                if (x >= 102 && x < 928 && y >= ny && y <= ny + (s >= 4)) base_rgb = 24'hbfb5a2;
                // 持键位置：同音所有可奏位置一起高亮。
                for (f = 0; f <= 12; f = f + 1) begin
                    if (open_note(s) + f >= 60 && open_note(s) + f <= 72 &&
                        key_down[open_note(s) + f - 60] &&
                        x >= 128 + f * 64 - 9 && x <= 128 + f * 64 + 9 &&
                        y >= ny - 7 && y <= ny + 7)
                        base_rgb = accent;
                end
            end
        end

        // ---- 文字层：标题 + 卡片标签 + 读数 + 键名/弦名 ----
        // 字形编号与 generate_ui_fonts.py 的分组严格对应（见该文件字符表）。
        // 标题拆成两次调用：每次最多 3 字，覆盖 4 字标题。
        if (!instrument_guitar) begin
            title4(40, 16, 3, {6'd1, 6'd2, 6'd3});   // 电子钢
            title4(40 + 3 * 52, 16, 1, {6'd4, 6'd0, 6'd0}); // 琴
        end else begin
            title4(40, 16, 3, {6'd1, 6'd2, 6'd5});   // 电子吉
            title4(40 + 3 * 52, 16, 1, {6'd6, 6'd0, 6'd0}); // 他
        end

        // 右上角“静奏”状态胶囊。
        text4(884, 34, 2, {6'd7, 6'd8, 12'd0}, C_MUTED);

        text4(48, 100, 2, {6'd9, 6'd10, 12'd0}, C_MUTED);    // 音量
        num4(226, 100, 3, {(volume < 100 ? 6'd0 : dg(volume_digits[11:8])),
                           (volume < 10  ? 6'd0 : dg(volume_digits[7:4])),
                           dg(volume_digits[3:0]), 6'd0}, C_TEXT);
        text4(368, 100, 2, {6'd11, 6'd9, 12'd0}, C_MUTED);   // 弯音
        // 读数“x.xx 半音”：整数位、十分位、百分位分开摆放，
        // 小数点与正负号由几何线条绘制，不占字库槽；数字用 24px 等宽字距。
        num4(492, 100, 1, {dg(bend_digits[11:8]), 18'd0}, C_TEXT);
        num4(528, 100, 1, {dg(bend_digits[7:4]),  18'd0}, C_TEXT);
        num4(552, 100, 1, {dg(bend_digits[3:0]),  18'd0}, C_TEXT);
        text4(592, 100, 2, {6'd12, 6'd9, 12'd0}, C_MUTED);   // 半音
        text4(736, 100, 3, {(octave == 0 ? 6'd13 : octave == 2 ? 6'd15 : 6'd14),
                            6'd9, 6'd16, 6'd0}, C_TEXT);     // 低/中/高音区
        text4(736, 136, 3, {6'd17, 6'd9, (sustain ? 6'd18 : 6'd19), 6'd0}, C_MUTED); // 延音开/关

        text4(48, 200, 4, {6'd20, 6'd21, 6'd22, 6'd23}, C_MUTED); // 实时波形
        text4(672, 200, 2, {6'd24, 6'd25, 12'd0}, C_MUTED);       // 倍率
        // ids 固定 4 槽 × 6bit，槽 0 是最高位；不足 4 字必须在“右侧”补 0，
        // 否则 18 位拼接被零扩展后整体左移一个字，读数会消失。
        num4(724, 200, (multiplier < 10 ? 2 : multiplier < 100 ? 3 : 4),
             (multiplier < 10)    ? {6'd47, dg(gain_digits[3:0]), 12'd0} :
             (multiplier < 100)   ? {6'd47, dg(gain_digits[7:4]), dg(gain_digits[3:0]), 6'd0} :
                                    {6'd47, dg(gain_digits[11:8]), dg(gain_digits[7:4]), dg(gain_digits[3:0])},
             accent);
        text4(832, 200, 4, {6'd37, 6'd38, 6'd1, 6'd39}, C_MUTED); // 输出电平

        // 符号与小数点用几何线条画，不占字库槽。
        // 正号=横线；负号=横线（更短）；小数点落在整数位与十分位之间。
        if (x >= 466 && x < 482 && y >= 119 && y < 122) base_rgb = accent;      // 符号横线
        if (!pitch_bend[15] && x >= 473 && x < 476 && y >= 113 && y < 128) base_rgb = accent; // 正号竖线
        if (x >= 518 && x < 522 && y >= 122 && y < 126) base_rgb = C_TEXT;      // 小数点

        if (!instrument_guitar) begin
            // 乐器名放在琴体上沿之上，避免 24px 字被键盘/指板覆盖。
            text4(40, 372, 2, {6'd3, 6'd4, 12'd0}, accent);     // 钢琴
            // 键名：C D E F G A B C5，放在白键底部；数字 5 对应字形 53。
            for (k = 0; k < 8; k = k + 1)
                text4(66 + k * 120, 530, 2, {white_letter(k), (k == 7 ? 6'd53 : 6'd52), 12'd0}, 24'h2f3c46);
        end else begin
            text4(40, 372, 4, {6'd33, 6'd34, 6'd35, 6'd36}, accent); // 指位示意
            // 弦名 E4 B3 G3 D3 A2 E2 放在指板左侧；数字 2/3/4 对应字形 50/51/52。
            text4(40, 408, 2, {6'd42, 6'd52, 12'd0}, C_MUTED);  // E4
            text4(40, 432, 2, {6'd46, 6'd51, 12'd0}, C_MUTED);  // B3
            text4(40, 456, 2, {6'd44, 6'd51, 12'd0}, C_MUTED);  // G3
            text4(40, 480, 2, {6'd41, 6'd51, 12'd0}, C_MUTED);  // D3
            text4(40, 504, 2, {6'd45, 6'd50, 12'd0}, C_MUTED);  // A2
            text4(40, 528, 2, {6'd42, 6'd50, 12'd0}, C_MUTED);  // E2
        end
    end
endmodule
