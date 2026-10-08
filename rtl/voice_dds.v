`timescale 1ns/1ps

// 一路DDS（直接数字合成）：相位累加器决定波表位置，ROM返回该位置的振幅。
// 全部逻辑使用clk；sample_tick只作“现在计算一个声音点”的使能。
// 改phase_inc改变音高，不改变正弦波形；本模块不处理按键和包络。
module voice_dds #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem"
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire [31:0]        phase_inc,
    output wire signed [15:0] sample,
    output wire               sample_valid
);
    wire [31:0] phase;
    wire [9:0] wave_addr;

    phase_acc u_phase_acc (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .phase_inc(phase_inc),
        .phase(phase),
        .wave_addr(wave_addr)
    );

    // 两个模块在同一个上升沿读取输入：ROM读的是更新前的旧相位地址，
    // phase_acc同时准备下次的相位。sample和sample_valid在本沿之后更新。
    // 复位相位为0，首个有效正弦样本为0属正常；不是看到0就没有成功发声。
    wave_lut #(.ROM_FILE(ROM_FILE)) u_wave_lut (
        .clk(clk),
        .rst(rst),
        .read_en(sample_tick),
        .addr(wave_addr),
        .sample(sample),
        .sample_valid(sample_valid)
    );
endmodule
