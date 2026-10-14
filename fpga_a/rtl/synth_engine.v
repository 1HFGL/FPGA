`timescale 1ns/1ps

module synth_engine #(
    parameter integer VOICES = 32
) (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_tick,
    input  wire [VOICES-1:0] voice_active,
    input  wire [VOICES-1:0] voice_gate,
    input  wire [VOICES*16-1:0] voice_trigger_id_flat,
    input  wire [VOICES*7-1:0] voice_note_flat,
    input  wire [VOICES*7-1:0] voice_velocity_flat,
    input  wire [VOICES*4-1:0] voice_timbre_flat,
    input  wire [VOICES*16-1:0] voice_pitch_bend_flat,
    input  wire [6:0] master_volume,
    input  wire [6:0] tone_brightness,
    output wire [VOICES-1:0] release_done,
    output wire [VOICES*16-1:0] release_trigger_id_flat,
    output wire [VOICES*16-1:0] voice_sample_flat,
    output wire signed [15:0] audio_sample
);

    genvar i;

    generate
        for (i = 0; i < VOICES; i = i + 1) begin : g_voice
            wire [6:0] note_i = voice_note_flat[i*7 +: 7];
            wire [1:0] wave_sel_i = voice_timbre_flat[i*4 +: 2];
            wire [31:0] phase_inc_i;
            reg  [31:0] phase_q;
            reg gate_d;
            reg [15:0] trigger_seen;
            wire [15:0] trigger_id = voice_trigger_id_flat[i*16 +: 16];
            wire retrigger = voice_active[i] && (trigger_id != trigger_seen);
            assign release_trigger_id_flat[i*16 +: 16] = trigger_seen;

            wire [7:0] lut_addr;
            wire signed [15:0] wave_sample;
            wire [15:0] env_level;
            wire rel_done;
            wire signed [15:0] gain_sample;

            phase_inc_calc u_phase_inc (
                .note      (note_i),
                .phase_inc (phase_inc_i)
            );

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    phase_q <= 32'd0;
                    gate_d  <= 1'b0;
                    trigger_seen <= 16'd0;
                end else if (sample_tick) begin
                    gate_d <= voice_gate[i];
                    trigger_seen <= trigger_id;
                    if (!voice_active[i]) begin
                        phase_q <= 32'd0;
                    end else if (retrigger || (voice_gate[i] && !gate_d)) begin
                        phase_q <= 32'd0;
                    end else begin
                        phase_q <= phase_q + phase_inc_i;
                    end
                end
            end

            assign lut_addr = phase_q[31:24];

            wave_lut u_wave_lut (
                .addr     (lut_addr),
                .wave_sel (wave_sel_i),
                .sample   (wave_sample)
            );

            adsr_envelope u_adsr_envelope (
                .clk          (clk),
                .rst_n        (rst_n),
                .sample_tick  (sample_tick),
                .gate         (voice_gate[i]),
                .retrigger    (retrigger),
                .level        (env_level),
                .release_done (rel_done)
            );

            voice_gain u_voice_gain (
                .wave_in    (wave_sample),
                .env_in     (env_level),
                .sample_out (gain_sample)
            );

            assign release_done[i] = rel_done;
            assign voice_sample_flat[i*16 +: 16] = gain_sample;
        end
    endgenerate

    wire signed [15:0] mixed_sample_raw;
    reg  signed [15:0] mixed_sample;
    wire signed [22:0] volume_product;
    wire signed [16:0] tone_diff;
    wire [3:0] tone_shift;
    wire signed [15:0] tone_sample;
    reg  signed [15:0] tone_state;

    poly_mixer_saturator #(
        .VOICES (VOICES)
    ) u_poly_mixer_saturator (
        .voice_sample_flat (voice_sample_flat),
        .audio_sample      (mixed_sample_raw)
    );

    // Run at the system clock, not sample_tick: the new frame settles one
    // clock after phase/envelope updates and is ready before the next tick.
    // A frame must allow at least two system clocks between sample ticks.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mixed_sample <= 16'sd0;
        else mixed_sample <= mixed_sample_raw;
    end

    // Global tone brightness: 127 bypasses; smaller values darken via one-pole LP.
    assign tone_diff   = mixed_sample - tone_state;
    assign tone_shift  = 4'd7 - tone_brightness[6:4];
    assign tone_sample = (tone_brightness == 7'd127) ? mixed_sample : tone_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_state <= 16'sd0;
        end else if (sample_tick) begin
            tone_state <= tone_state + (tone_diff >>> tone_shift);
        end
    end

    assign volume_product = tone_sample * $signed({1'b0, master_volume});
    assign audio_sample = volume_product[22:7];

endmodule
