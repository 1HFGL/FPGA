`timescale 1ns/1ps

// 单声部连接：正弦 DDS 产生波形，ADSR 产生音量，乘法器将两者相乘。
// 信号端口与 v1 一致；STEP 参数升级为以采样点为单位的 SAMPLES 参数。
// DDS（直接数字合成）负责“多高的音”；ADSR（起音/衰减/保持/释放）负责
// “这个音随时间多响”。二者相乘仍是实时合成，不是播放钢琴录音。
// gate只控制包络，不重置DDS相位；松键后的请求也不能停，否则尾音会冻结。
module voice_adsr #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem",
    parameter [31:0] ATTACK_SAMPLES  = 32'd96,
    parameter [31:0] DECAY_SAMPLES   = 32'd24000,
    parameter [16:0] SUSTAIN_LEVEL   = 17'd6554,
    parameter [31:0] RELEASE_SAMPLES = 32'd5760
) (
    input  wire               clk,
    input  wire               rst,          // 高有效同步复位
    input  wire               sample_tick,  // 外部音频请求，松键后仍需继续
    input  wire [31:0]        phase_inc,
    input  wire               gate,         // 按住状态，已同步/消抖
    input  wire               retrigger,    // 重触发单拍脉冲，未使用时接 0
    output wire signed [15:0] sample,
    output wire               sample_valid,
    output wire [16:0]        env_level,    // 当前包络，仅作为观察输出
    output wire               voice_active  // 包络及最后一个非零输出尚未结束
);
    wire signed [15:0] raw_sample;
    wire raw_valid;
    wire env_active;
    wire [2:0] env_state;

    // 显式传 ROM_FILE，避免内部 DDS 默认值与外层工程设置不一致。
    voice_dds #(.ROM_FILE(ROM_FILE)) u_dds (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .phase_inc(phase_inc), .sample(raw_sample), .sample_valid(raw_valid)
    );
    adsr_env #(
        .ATTACK_SAMPLES(ATTACK_SAMPLES), .DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .RELEASE_SAMPLES(RELEASE_SAMPLES)
    ) u_env (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .gate(gate), .retrigger(retrigger), .env_level(env_level),
        .active(env_active), .state(env_state)
    );

    // E 上升沿接到请求：DDS 与包络同时更新第 n 个采样所需的值。
    // E+1 上升沿之后：乘法结果与 sample_valid 同时输出。
    // 同步下游在 E+2 上升沿读取结果；连续请求也能逐拍对应。
    // env_level 是本拍的包络，连续请求时比 sample 领先一拍，勿再直接相乘。
    sample_gain u_gain (
        .clk(clk), .rst(rst), .in_valid(raw_valid), .sample_in(raw_sample),
        .gain(env_level), .sample_out(sample), .out_valid(sample_valid)
    );

    // 释放到零时，流水线可能仍输出上一个非零样本，因此不能仅用 gate
    // 或 env_active 判断该声部已经可被重新分配。
    assign voice_active=env_active | (sample_valid && (sample!=16'sd0));
endmodule
