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
module instrument_display #(
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
        instrument_panel_ui #(.CONTROL_FEATURES(CONTROL_FEATURES),.TOUCH_PANEL(TOUCH_PANEL),.ENABLE_GUIDE(ENABLE_GUIDE),
            .LOG_METER(1),.SHOW_BRIGHTNESS(BRIGHTNESS_PANEL),.FRAME_BEND(1),.PIPELINE_MAP(1)) u_renderer(
            // 与state_frame同沿读取state_latest，数字和符号不会错开一帧。
            .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.frame_commit(commit),
            .pitch_bend_latest(state_latest[35:20]),
            // This edge also captures x_d/y_d and commits state_frame.
            .map_x_early(x),.map_y_early(y),
            .map_guitar_early(commit?state_latest[39]:state_frame[39]),
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
