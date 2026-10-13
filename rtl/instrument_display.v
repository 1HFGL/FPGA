// B部分通用显示入口：800x480 RGB888、13键、参数状态、256点波形。
// sys_* 输入均同步于 sys_clk；pixel_clk 单独输入，禁止把未同步数据直接接渲染器。
// rst_n 是两显示时钟域共同复位，板级应合并外部复位和像素PLL失锁；各域内部同步释放。
// 本模块不生成PLL、不分配封装脚、不驱动背光供电，不是可直接下载的板级顶层。
module instrument_display #(
    parameter integer H_FRONT=40, H_SYNC=128, H_BACK=88,
    parameter integer V_FRONT=13, V_SYNC=2, V_BACK=30,
    parameter integer HS_ACTIVE=0, VS_ACTIVE=0,
    parameter integer WAVE_GAIN_SHIFT=3 // 0..8，仅放大屏幕波形，不改变音频
) (
    input wire sys_clk, pixel_clk, rst_n,
    input wire [12:0] key_down, // bit0..12 = 当前档位的C,C#,D,...,B,C
    input wire [6:0] volume, // 0..127
    input wire signed [15:0] pitch_bend, // 显示归一化码：-32768..32767 对应 -2..+2半音
    input wire [1:0] octave, // 0低/1中/2高；3显示为中档
    input wire sustain, instrument_guitar, // 音色状态：0钢琴，1吉他；不是切换命令
    input wire audio_valid,
    input wire signed [15:0] audio_sample, // 最终混音后的样本副本，每次valid代表一个样本
    output reg [23:0] lcd_rgb,
    output reg lcd_de, lcd_hsync, lcd_vsync,
    output reg frame_start, // 与输出RGB/DE同拍，像素域单周期脉冲
    output wire display_sample_drop // sys_clk域，信箱忙时丢失显示样本；绝不反压音频
);
    reg [1:0] sys_release, pixel_release;
    always @(posedge sys_clk or negedge rst_n)
        if (!rst_n) sys_release<=0;
        else sys_release<={sys_release[0],1'b1};
    always @(posedge pixel_clk or negedge rst_n)
        if (!rst_n) pixel_release<=0;
        else pixel_release<={pixel_release[0],1'b1};
    wire sys_rst_n=sys_release[1], pixel_rst_n=pixel_release[1];
    wire [39:0] state_latest;
    reg [39:0] state_frame;
    wire [15:0] sample_pixel;
    wire sample_pixel_valid, sample_ready;
    display_cdc_latest #(.WIDTH(40)) u_status (
        .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_valid(1'b1),
        .src_data({instrument_guitar,sustain,octave,pitch_bend,volume,key_down}),.src_ready(),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_valid(),.dst_data(state_latest));
    display_cdc_latest #(.WIDTH(16)) u_sample (
        .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_valid(audio_valid),
        .src_data(audio_sample),.src_ready(sample_ready),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),
        .dst_valid(sample_pixel_valid),.dst_data(sample_pixel));
    assign display_sample_drop=sys_rst_n && audio_valid && !sample_ready;

    wire [11:0] x,y;
    wire de,hs,vs,start,commit;
    lcd_rgb_timing #(.H_FRONT(H_FRONT),.H_SYNC(H_SYNC),.H_BACK(H_BACK),
        .V_FRONT(V_FRONT),.V_SYNC(V_SYNC),.V_BACK(V_BACK),
        .HS_ACTIVE(HS_ACTIVE),.VS_ACTIVE(VS_ACTIVE)) u_timing (
        .pixel_clk(pixel_clk),.rst_n(pixel_rst_n),.x(x),.y(y),
        .de(de),.hsync(hs),.vsync(vs),.frame_start(start),.frame_commit(commit));

    // 先符号扩展再放大；饱和后取高8位，禁止大信号溢出翻转波形。
    wire signed [31:0] expanded={{16{sample_pixel[15]}},sample_pixel};
    wire signed [31:0] amplified=expanded <<< WAVE_GAIN_SHIFT;
    wire [7:0] sample8=(amplified>32'sd32767) ? 8'h7f :
                       (amplified< -32'sd32768) ? 8'h80 : amplified[15:8];
    wire [11:0] wave_offset=x-12'd144;
    wire [7:0] wave_address=(x>=144 && x<656) ? wave_offset[8:1] : 8'd0;
    wire [7:0] wave_data;
    wire wave_ready;
    display_wave_buffer u_wave (
        .pixel_clk(pixel_clk),.rst_n(pixel_rst_n),.sample_valid(sample_pixel_valid),
        .sample_data(sample8),.frame_commit(commit),.read_addr(wave_address),
        .read_data(wave_data),.wave_ready(wave_ready));

    // RAM读一拍，坐标和同步信号也延迟一拍；渲染后所有屏幕信号再统一寄存一拍。
    reg [11:0] x_d,y_d;
    reg de_d,hs_d,vs_d,start_d,wave_ready_d;
    wire [23:0] pixel_color;
    piano_display_renderer u_renderer (
        .x(x_d),.y(y_d),.key_down(state_frame[12:0]),.volume(state_frame[19:13]),
        .pitch_bend(state_frame[35:20]),.octave(state_frame[37:36]),
        .sustain(state_frame[38]),.instrument_guitar(state_frame[39]),
        .wave_data(wave_data),.wave_ready(wave_ready_d),.rgb(pixel_color));
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            state_frame<=0;
            x_d<=0; y_d<=0; de_d<=0; start_d<=0; wave_ready_d<=0;
            hs_d<=(HS_ACTIVE==0); vs_d<=(VS_ACTIVE==0);
            lcd_rgb<=0; lcd_de<=0; frame_start<=0;
            lcd_hsync<=(HS_ACTIVE==0); lcd_vsync<=(VS_ACTIVE==0);
        end else begin
            if (commit) state_frame<=state_latest;
            x_d<=x; y_d<=y; de_d<=de; hs_d<=hs; vs_d<=vs; start_d<=start;
            wave_ready_d<=wave_ready;
            lcd_rgb<=de_d ? pixel_color : 24'd0;
            lcd_de<=de_d; lcd_hsync<=hs_d; lcd_vsync<=vs_d; frame_start<=start_d;
        end
    end
endmodule
