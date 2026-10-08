`timescale 1ns/1ps

// 四声部独立合成核心；不是声部分配器，不直接连接物理按键。
// R0 接受采样请求：DDS 查旧相位，更新各自包络，快照各自增益。
// R1 单声部 ADSR 样本就绪；R2 增益样本就绪；R3 混音及 valid 就绪。
// 同步下游在 R4 读取输出。支持连续请求，各拍数据一一对应。
// 这里的R0/R1/...是相邻系统时钟上升沿，50MHz下每拍20ns，不是音频帧。
// 读图：每路 note -> note_phase_lut -> voice_adsr -> sample_gain -> sample_mixer4。
// 第一只sample_gain在voice_adsr里乘包络；第二只在本文件乘固定/外部增益。
// 两者作用不同，不能看见两个乘法模块就直接删掉其中一个。
// *_flat只表示打包连线：第v路7位字段是[v*7 +: 7]，不是混在一起算音符。
module voice_bank_adsr #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem",
    parameter [31:0] ATTACK_SAMPLES  = 32'd96,
    parameter [31:0] DECAY_SAMPLES   = 32'd24000,
    parameter [16:0] SUSTAIN_LEVEL   = 17'd6554,
    parameter [31:0] RELEASE_SAMPLES = 32'd5760,
    parameter integer MIX_SHIFT = 5
) (
    input  wire               clk,
    input  wire               rst_n, // 低有效同步复位，需来自统一复位逻辑
    input  wire               sample_request, // 松键后仍须持续提供
    input  wire [3:0]         voice_gate,
    input  wire [3:0]         voice_retrigger, // 每路单 clk 脉冲，不是保持状态
    input  wire [27:0]        voice_note_flat, // 四个 7 位 MIDI 音符，声部 0 在低位
    input  wire [27:0]        voice_velocity_flat, // 兼容旧 demo 的增益字段
    output wire [3:0]         release_done,
    output wire [3:0]         voice_active, // 保持/包络/流水线尾音任一仍存在
    output wire [67:0]        env_level_flat, // 四个无符号 Q1.16 电平，仅供观察
    output wire               sounding,
    output wire signed [15:0] sample_data,
    output wire               sample_valid,
    output wire               sample_clipped
);
    wire rst = ~rst_n;
    wire [3:0] adsr_active, gain_valid;
    wire [63:0] gain_samples;
    reg request_d1;
    reg [3:0] mixed_nonzero;
    genvar v;

    always @(posedge clk) begin
        if (rst) request_d1 <= 1'b0;
        else request_d1 <= sample_request;
    end

    generate for (v=0; v<4; v=v+1) begin: g_voice
        // generate在综合时展开成四套硬件，不是用软件循环轮流播放四段录音。
        // 每路内部相位和包络寄存器独立，所有声部同时收到同一个采样请求。
        wire [31:0] phase_inc;
        wire signed [15:0] adsr_sample;
        wire adsr_valid;
        wire signed [15:0] gain_sample;
        reg [6:0] velocity_d0, velocity_d1;
        // 0 为静音，127 为单位增益；1~126 按 velocity/128 缩放。
        // 这只是兼容的数字增益输入，不表示新增按键力度传感器。
        wire [16:0] velocity_gain = (velocity_d1==7'd127) ?
                                     17'd65536 : {1'b0,velocity_d1,9'd0};

        note_phase_lut u_note (
            .note(voice_note_flat[v*7 +: 7]), .phase_inc(phase_inc)
        );
        voice_adsr #(
            .ROM_FILE(ROM_FILE), .ATTACK_SAMPLES(ATTACK_SAMPLES),
            .DECAY_SAMPLES(DECAY_SAMPLES), .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
            .RELEASE_SAMPLES(RELEASE_SAMPLES)
        ) u_voice (
            .clk(clk), .rst(rst), .sample_tick(sample_request),
            .phase_inc(phase_inc), .gate(voice_gate[v]),
            .retrigger(voice_retrigger[v]),
            .sample(adsr_sample), .sample_valid(adsr_valid),
            .env_level(env_level_flat[v*17 +: 17]), .voice_active(adsr_active[v])
        );
        // 连续请求时，输入增益可能每拍改变，必须跟随其对应样本。
        // R0锁存velocity_d0，R1移到velocity_d1，R2乘法器读取旧velocity_d1；
        // 直接接实时voice_velocity_flat会把新音量错配给前一个音频样本。
        always @(posedge clk) begin
            if (rst) begin velocity_d0<=0; velocity_d1<=0; end
            else begin
                if (sample_request) velocity_d0<=voice_velocity_flat[v*7 +: 7];
                if (request_d1) velocity_d1<=velocity_d0;
            end
        end
        sample_gain u_velocity (
            .clk(clk), .rst(rst), .in_valid(adsr_valid), .sample_in(adsr_sample),
            .gain(velocity_gain), .sample_out(gain_sample), .out_valid(gain_valid[v])
        );
        assign gain_samples[v*16 +: 16] = gain_sample;

        // 按声部分别跟踪最后参与混音的样本，避免总和相消时误报空闲。
        // flag 在无请求时保持；尾音最终的零样本到达 R3 后才清除。
        always @(posedge clk) begin
            if (rst) mixed_nonzero[v]<=1'b0;
            else if (&gain_valid) mixed_nonzero[v]<=(gain_sample!=16'sd0);
        end
        assign voice_active[v] = !rst && (voice_gate[v] | adsr_active[v] |
                                 (gain_valid[v] && gain_sample!=16'sd0) |
                                 mixed_nonzero[v]);
        assign release_done[v] = rst || (!voice_gate[v] && !voice_active[v]);
    end endgenerate

    // release_done是“可以回收”的电平，不是一个clk脉冲；C须同时检查gate已松开。
    // |为归约或：只要任意声部含尾音，就维持输出使能。
    assign sounding = |voice_active;
    // 四路共用请求/复位，valid 应始终一致；测试同时检查该约定。
    sample_mixer4 #(.MIX_SHIFT(MIX_SHIFT)) u_mix (
        .clk(clk), .rst(rst), .in_valid(&gain_valid), .samples_flat(gain_samples),
        .sample_out(sample_data), .out_valid(sample_valid), .clipped(sample_clipped)
    );
endmodule
