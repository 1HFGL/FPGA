`timescale 1ns/1ps

// Existing DDS plus ADSR; keeps the original voice_dds interface untouched.
module voice_adsr #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem",
    parameter [16:0] ATTACK_STEP   = 17'd137,
    parameter [16:0] DECAY_STEP    = 17'd7,
    parameter [16:0] SUSTAIN_LEVEL = 17'd32768,
    parameter [16:0] RELEASE_STEP  = 17'd3
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire [31:0]        phase_inc,
    input  wire               gate,
    input  wire               retrigger,
    output wire signed [15:0] sample,
    output wire               sample_valid,
    output wire [16:0]        env_level,
    output wire               voice_active
);
    wire signed [15:0] raw_sample;
    wire raw_valid;
    wire env_active;
    wire [2:0] env_state;

    voice_dds #(.ROM_FILE(ROM_FILE)) u_dds (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .phase_inc(phase_inc), .sample(raw_sample), .sample_valid(raw_valid)
    );
    adsr_env #(
        .ATTACK_STEP(ATTACK_STEP), .DECAY_STEP(DECAY_STEP),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .RELEASE_STEP(RELEASE_STEP)
    ) u_env (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .gate(gate), .retrigger(retrigger), .env_level(env_level),
        .active(env_active), .state(env_state)
    );

    // Request edge E: DDS and envelope both register sample n.
    // E+1: multiply those matching values and register sample/valid.
    // Back-to-back requests are supported; idle output samples are held.
    sample_gain u_gain (
        .clk(clk), .rst(rst), .in_valid(raw_valid), .sample_in(raw_sample),
        .gain(env_level), .sample_out(sample), .out_valid(sample_valid)
    );

    // Keep the voice owned through the last nonzero pipeline output.
    // gate=0 does NOT disable sample_tick: release must keep receiving ticks.
    assign voice_active = env_active | (sample_valid && (sample != 16'sd0));
endmodule
