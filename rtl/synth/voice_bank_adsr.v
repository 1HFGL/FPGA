`timescale 1ns/1ps

// 参数化独立声部合成：正式16路，默认4路用于接口兼容和单元验证。
// 默认控制关闭：R0 DDS/包络，R1包络乘法，R2力度，R3混音，R4下游接收。
// 控制启用：R0弯音乘法与控制快照，R1 DDS/包络，R4混音，R5下游接收。
// 支持连续请求，每拍控制跟随对应样本；正式音频请求约每1042个系统拍一次。
// 这里的R0/R1/...是相邻系统时钟上升沿，50MHz下每拍20ns，不是音频帧。
// 每路note -> 音高表 -> 全局弯音频率比 -> voice_timbre_adsr -> 力度增益 -> 平衡混音。
// 第一只sample_gain在voice_adsr里乘包络；第二只在本文件乘固定/外部增益。
// 两者作用不同，不能看见两个乘法模块就直接删掉其中一个。
// *_flat只表示打包连线：第v路7位字段是[v*7 +: 7]，不是混在一起算音符。
module voice_bank_adsr #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem",
    parameter [31:0] ATTACK_SAMPLES  = 32'd96,
    parameter [31:0] DECAY_SAMPLES   = 32'd24000,
    parameter [16:0] SUSTAIN_LEVEL   = 17'd6554,
    parameter [31:0] RELEASE_SAMPLES = 32'd5760,
    parameter integer MIX_SHIFT = 5,
    parameter BRIGHT_ROM_FILE = "rtl/rom/bright_1024.mem",
    parameter integer VOICES=4,
    parameter integer ENABLE_CONTROLS=0
) (
    input  wire               clk,
    input  wire               rst_n, // 低有效同步复位，需来自统一复位逻辑
    input  wire               sample_request, // 松键后仍须持续提供
    input  wire [VOICES-1:0] voice_gate,
    input  wire [VOICES-1:0] voice_retrigger,
    input  wire [VOICES*7-1:0] voice_note_flat,
    input  wire [VOICES*7-1:0] voice_velocity_flat,
    output wire [VOICES-1:0] release_done,
    output wire [VOICES-1:0] voice_active,
    output wire [VOICES*17-1:0] env_level_flat,
    output wire               sounding,
    output wire signed [15:0] sample_data,
    output wire               sample_valid,
    output wire               sample_clipped,
    input  wire [VOICES-1:0] voice_timbre,
    input wire [VOICES*16-1:0] voice_trigger_id_flat,
    output wire [VOICES*16-1:0] release_trigger_id_flat,
    input wire [17:0] bend_ratio // 无符号Q2.16；65536=原音高，作用于全部声部
);
    wire rst = ~rst_n;
    wire [VOICES-1:0] adsr_active, gain_valid;
    wire [VOICES*16-1:0] gain_samples;
    reg request_d1;
    wire core_request=ENABLE_CONTROLS ? request_d1 : sample_request;
    reg core_request_d1;
    reg [VOICES-1:0] mixed_nonzero;
    genvar v;

    always @(posedge clk) begin
        if (rst) begin request_d1<=1'b0;core_request_d1<=1'b0;end
        else begin request_d1<=sample_request;core_request_d1<=core_request;end
    end

    generate for (v=0; v<VOICES; v=v+1) begin: g_voice
        // generate在综合时展开成VOICES套硬件，相位/音高/包络分别独立。
        // 每路内部相位和包络寄存器独立，所有声部同时收到同一个采样请求。
        wire [31:0] base_phase_inc;
        wire [49:0] bent_product=base_phase_inc*bend_ratio;
        reg [49:0] product_d0;
        reg gate_d0,retrigger_d0,timbre_d0;
        reg [6:0] velocity_snapshot;
        reg [15:0] id_d0;
        wire [50:0] bent_rounded={1'b0,product_d0}+51'd32768;
        wire [31:0] phase_inc=ENABLE_CONTROLS ? bent_rounded[47:16] : base_phase_inc;
        reg [15:0] consumed_id;
        // 只在真正采样沿确认代次；gate已松开的短音也确认，避免槽永不回收。
        wire new_generation=ENABLE_CONTROLS && (voice_trigger_id_flat[v*16+:16]!=consumed_id);
        wire retrigger=ENABLE_CONTROLS ? (core_request && retrigger_d0) : voice_retrigger[v];
        always @(posedge clk) begin
            if(rst) begin
                consumed_id<=0;product_d0<=0;gate_d0<=0;retrigger_d0<=0;timbre_d0<=0;velocity_snapshot<=0;id_d0<=0;
            end else begin
                // R0：乘法器输出寄存，整组控制同时快照，不能拼接不同代次的样本。
                if(sample_request) begin
                    product_d0<=bent_product;gate_d0<=voice_gate[v];
                    // 与上一次接受的请求比较，连续请求时不能因确认晚一拍重复触发。
                    retrigger_d0<=(voice_trigger_id_flat[v*16+:16]!=id_d0);
                    timbre_d0<=voice_timbre[v];velocity_snapshot<=voice_velocity_flat[v*7+:7];
                    id_d0<=voice_trigger_id_flat[v*16+:16];
                end
                if(core_request) consumed_id<=ENABLE_CONTROLS ? id_d0 : voice_trigger_id_flat[v*16+:16];
            end
        end
        assign release_trigger_id_flat[v*16+:16]=consumed_id;
        wire signed [15:0] adsr_sample;
        wire adsr_valid;
        wire signed [15:0] gain_sample;
        reg [6:0] velocity_d0, velocity_d1;
        // 0 为静音，127 为单位增益；1~126 按 velocity/128 缩放。
        // 这只是兼容的数字增益输入，不表示新增按键力度传感器。
        wire [16:0] velocity_gain = (velocity_d1==7'd127) ?
                                     17'd65536 : {1'b0,velocity_d1,9'd0};

        note_phase_lut u_note (
            .note(voice_note_flat[v*7 +: 7]), .phase_inc(base_phase_inc)
        );
        voice_timbre_adsr #(
            .BRIGHT_ROM_FILE(BRIGHT_ROM_FILE),
            .ROM_FILE(ROM_FILE), .ATTACK_SAMPLES(ATTACK_SAMPLES),
            .DECAY_SAMPLES(DECAY_SAMPLES), .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
            .RELEASE_SAMPLES(RELEASE_SAMPLES)
        ) u_voice (
            .clk(clk), .rst(rst), .sample_tick(core_request),
            .phase_inc(phase_inc), .gate(ENABLE_CONTROLS ? gate_d0 : voice_gate[v]),
            .retrigger(retrigger), .timbre(ENABLE_CONTROLS ? timbre_d0 : voice_timbre[v]),
            .sample(adsr_sample), .sample_valid(adsr_valid),
            .env_level(env_level_flat[v*17 +: 17]), .voice_active(adsr_active[v])
        );
        // 连续请求时，输入增益可能每拍改变，必须跟随其对应样本。
        // R0锁存velocity_d0，R1移到velocity_d1，R2乘法器读取旧velocity_d1；
        // 直接接实时voice_velocity_flat会把新音量错配给前一个音频样本。
        always @(posedge clk) begin
            if (rst) begin velocity_d0<=0; velocity_d1<=0; end
            else begin
                if (core_request) velocity_d0<=ENABLE_CONTROLS ? velocity_snapshot : voice_velocity_flat[v*7 +: 7];
                if (core_request_d1) velocity_d1<=velocity_d0;
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
        assign release_done[v] = rst || (!voice_gate[v] && !voice_active[v] && !new_generation);
    end endgenerate

    // release_done是“可以回收”的电平，不是一个clk脉冲；C须同时检查gate已松开。
    // |为归约或：只要任意声部含尾音，就维持输出使能。
    assign sounding = |voice_active;
    // 四路共用请求/复位，valid 应始终一致；测试同时检查该约定。
    sample_mixer4 #(.MIX_SHIFT(MIX_SHIFT),.VOICES(VOICES)) u_mix (
        .clk(clk), .rst(rst), .in_valid(&gain_valid), .samples_flat(gain_samples),
        .sample_out(sample_data), .out_valid(sample_valid), .clipped(sample_clipped)
    );
endmodule
