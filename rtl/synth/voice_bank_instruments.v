`timescale 1ns/1ps

// 四声部独立合成核心；不是声部分配器，不直接连接物理按键。
// R0 接受采样请求：DDS 查旧相位，更新各自包络，快照各自增益。
// R1 亮度乘法；R2 声部ADSR样本；R3 力度；R4 混音及valid。
// 同步下游在 R5 读取输出。支持连续请求，各拍数据一一对应。
module voice_bank_instruments #(
    parameter SINE_ROM_FILE="rtl/rom/sine_1024.mem",
    parameter GUITAR_ROM_FILE="rtl/rom/guitar_1024.mem",
    parameter STRINGS_ROM_FILE="rtl/rom/strings_1024.mem",
    parameter [31:0] G_ATTACK=32'd64, G_DECAY=32'd32768, G_RELEASE=32'd4096,
    parameter [16:0] G_SUSTAIN=17'd0,
    parameter [31:0] S_ATTACK=32'd1024, S_DECAY=32'd8192, S_RELEASE=32'd8192,
    parameter [16:0] S_SUSTAIN=17'd49152,
    parameter [31:0] G_TONE_SAMPLES=32'd8192, S_TONE_SAMPLES=32'd2048,
    parameter integer MIX_SHIFT=5
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
    output wire               sample_clipped,
    input  wire [3:0]         voice_instrument, // 0拨弦/1弦乐；新触发时采纳
    output wire [3:0]         instrument_active,
    output wire [67:0]        tone_level_flat
);
    wire rst = ~rst_n;
    wire [3:0] adsr_active, gain_valid;
    wire [63:0] gain_samples;
    reg request_d1, request_d2;
    reg [3:0] mixed_nonzero;
    genvar v;

    always @(posedge clk) begin
        if (rst) begin request_d1<=0; request_d2<=0; end
        else begin request_d1<=sample_request; request_d2<=request_d1; end
    end

    generate for (v=0; v<4; v=v+1) begin: g_voice
        wire [31:0] phase_inc;
        wire signed [15:0] adsr_sample;
        wire adsr_valid;
        wire signed [15:0] gain_sample;
        reg [6:0] velocity_d0, velocity_d1, velocity_d2;
        // 0 为静音，127 为单位增益；1~126 按 velocity/128 缩放。
        // 这只是兼容的数字增益输入，不表示新增按键力度传感器。
        wire [16:0] velocity_gain = (velocity_d2==7'd127) ?
                                     17'd65536 : {1'b0,velocity_d2,9'd0};

        note_phase_lut u_note (
            .note(voice_note_flat[v*7 +: 7]), .phase_inc(phase_inc)
        );
        voice_instrument #(
            .SINE_ROM_FILE(SINE_ROM_FILE),.GUITAR_ROM_FILE(GUITAR_ROM_FILE),
            .STRINGS_ROM_FILE(STRINGS_ROM_FILE),
            .G_ATTACK(G_ATTACK), .G_DECAY(G_DECAY), .G_SUSTAIN(G_SUSTAIN), .G_RELEASE(G_RELEASE),
        .S_ATTACK(S_ATTACK), .S_DECAY(S_DECAY), .S_SUSTAIN(S_SUSTAIN), .S_RELEASE(S_RELEASE),
            .G_TONE_SAMPLES(G_TONE_SAMPLES),.S_TONE_SAMPLES(S_TONE_SAMPLES)
        ) u_voice (
            .clk(clk),.rst(rst),.sample_tick(sample_request),.phase_inc(phase_inc),
            .gate(voice_gate[v]),.retrigger(voice_retrigger[v]),.instrument(voice_instrument[v]),
            .sample(adsr_sample),.sample_valid(adsr_valid),.env_level(env_level_flat[v*17 +: 17]),
            .tone_level(tone_level_flat[v*17 +: 17]),.active_instrument(instrument_active[v]),
            .voice_active(adsr_active[v]));
        // 连续请求时，输入增益可能每拍改变，必须跟随其对应样本。
        always @(posedge clk) begin
            if (rst) begin velocity_d0<=0; velocity_d1<=0; velocity_d2<=0; end
            else begin
                if (sample_request) velocity_d0<=voice_velocity_flat[v*7 +: 7];
                if (request_d1) velocity_d1<=velocity_d0;
                if (request_d2) velocity_d2<=velocity_d1;
            end
        end
        sample_gain u_velocity (
            .clk(clk), .rst(rst), .in_valid(adsr_valid), .sample_in(adsr_sample),
            .gain(velocity_gain), .sample_out(gain_sample), .out_valid(gain_valid[v])
        );
        assign gain_samples[v*16 +: 16] = gain_sample;

        // 按声部分别跟踪最后参与混音的样本，避免总和相消时误报空闲。
        // flag 在无请求时保持；尾音最终的零样本到达 R4 后才清除。
        always @(posedge clk) begin
            if (rst) mixed_nonzero[v]<=1'b0;
            else if (&gain_valid) mixed_nonzero[v]<=(gain_sample!=16'sd0);
        end
        assign voice_active[v] = !rst && (voice_gate[v] | adsr_active[v] |
                                 (gain_valid[v] && gain_sample!=16'sd0) |
                                 mixed_nonzero[v]);
        assign release_done[v] = rst || (!voice_gate[v] && !voice_active[v]);
    end endgenerate

    assign sounding = |voice_active;
    // 四路共用请求/复位，valid 应始终一致；测试同时检查该约定。
    sample_mixer4 #(.MIX_SHIFT(MIX_SHIFT)) u_mix (
        .clk(clk), .rst(rst), .in_valid(&gain_valid), .samples_flat(gain_samples),
        .sample_out(sample_data), .out_valid(sample_valid), .clipped(sample_clipped)
    );
endmodule
