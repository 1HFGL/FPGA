`timescale 1ns/1ps
// Two serial 16-voice engines execute the same frame in parallel.
// One physical dual-port coefficient ROM; one distortion/cabinet/master stage.
// R897 group buses -> R898 registered 32-voice sums -> R925 PCM valid.
module voice_bank_dual16 #(
    parameter integer MIX_SHIFT = 3,
    parameter [31:0] P_RELEASE = 4096, G_RELEASE = 2048,
    parameter SHAPER_ROM_FILE = "rtl/rom/rock_v2_shaper.mem",
    parameter SINE_ROM_FILE = "rtl/rom/sine_1024.mem"
)(
    input wire clk, rst_n, sample_request,
    input wire [16:0] global_gain_q16, pitch_ratio_q16,
    input wire [31:0] voice_gate, voice_retrigger, voice_instrument,
    input wire [223:0] voice_note_flat, voice_velocity_flat,
    output wire [31:0] voice_active, release_done, instrument_active,
    output wire [543:0] env_level_flat,
    output wire sounding, busy,
    output wire signed [15:0] sample_data,
    output wire sample_valid, sample_clipped,
    output reg overrun
);
    // 两组在同一accept沿取样；公共增益只在最终输出级应用一次。
    reg in_flight, output_start;
    reg [16:0] gain_latched;
    wire accept = sample_request && !busy;
    assign busy = in_flight;
    wire [1:0] group_done, group_overrun, rom_enable;
    wire [13:0] address_a, address_b;
    wire [6:0] metadata_a, metadata_b;
    wire [75:0] cfg_a, cfg_b;
    wire signed [21:0] piano_a, piano_b, guitar_a, guitar_b;
    reg signed [21:0] piano_sum, guitar_sum;
    // Each group contains <=16 signed 16-bit voices. Their sum fits 21 signed
    // bits; the 22-bit buses preserve the original algorithm before any shifts.
    always @(posedge clk) begin
        if (!rst_n) begin
            in_flight <= 0;
            output_start <= 0;
            overrun <= 0;
            gain_latched <= 65536;
            piano_sum <= 0;
            guitar_sum <= 0;
        end else begin
            output_start <= (& group_done);
            if (accept) begin
                in_flight <= 1;
                gain_latched <= global_gain_q16;
            end
            else if (sample_valid) in_flight <= 0;
            if (& group_done) begin
                piano_sum <= piano_a + piano_b;
                guitar_sum <= guitar_a + guitar_b;
            end
            // 两组完成脉冲必须同拍；错拍与忙时重入均锁存为overrun，直到复位。
            if ((sample_request && busy) || (| group_overrun) || (group_done[0] ^ group_done[1])) overrun <= 1;
        end
    end
    modal_coeff_rom_dual u_coefficients(
        .clk(clk),
        .en_a(rom_enable[0]),
        .en_b(rom_enable[1]),
        .address_a(address_a),
        .address_b(address_b),
        .metadata_a(metadata_a),
        .metadata_b(metadata_b),
        .data_a(cfg_a),
        .data_b(cfg_b)
    );
    modal_voice_group16 #(
        .VOICE_OFFSET(0),
        .P_RELEASE(P_RELEASE),
        .G_RELEASE(G_RELEASE),
        .SINE_ROM_FILE(SINE_ROM_FILE)
    ) u_group0(
        .clk(clk),
        .rst_n(rst_n),
        .sample_request(accept),
        .pitch_ratio_q16(pitch_ratio_q16),
        .voice_gate(voice_gate[15:0]),
        .voice_retrigger(voice_retrigger[15:0]),
        .voice_instrument(voice_instrument[15:0]),
        .voice_note_flat(voice_note_flat[111:0]),
        .voice_velocity_flat(voice_velocity_flat[111:0]),
        .coefficient_data(cfg_a),
        .coefficient_enable(rom_enable[0]),
        .coefficient_address(address_a),
        .coefficient_metadata(metadata_a),
        .voice_active(voice_active[15:0]),
        .release_done(release_done[15:0]),
        .instrument_active(instrument_active[15:0]),
        .env_level_flat(env_level_flat[271:0]),
        .busy(),
        .sample_valid(group_done[0]),
        .overrun(group_overrun[0]),
        .piano_bus(piano_a),
        .guitar_bus(guitar_a)
    );
    modal_voice_group16 #(
        .VOICE_OFFSET(16),
        .P_RELEASE(P_RELEASE),
        .G_RELEASE(G_RELEASE),
        .SINE_ROM_FILE(SINE_ROM_FILE)
    ) u_group1(
        .clk(clk),
        .rst_n(rst_n),
        .sample_request(accept),
        .pitch_ratio_q16(pitch_ratio_q16),
        .voice_gate(voice_gate[31:16]),
        .voice_retrigger(voice_retrigger[31:16]),
        .voice_instrument(voice_instrument[31:16]),
        .voice_note_flat(voice_note_flat[223:112]),
        .voice_velocity_flat(voice_velocity_flat[223:112]),
        .coefficient_data(cfg_b),
        .coefficient_enable(rom_enable[1]),
        .coefficient_address(address_b),
        .coefficient_metadata(metadata_b),
        .voice_active(voice_active[31:16]),
        .release_done(release_done[31:16]),
        .instrument_active(instrument_active[31:16]),
        .env_level_flat(env_level_flat[543:272]),
        .busy(),
        .sample_valid(group_done[1]),
        .overrun(group_overrun[1]),
        .piano_bus(piano_b),
        .guitar_bus(guitar_b)
    );
    modal_shared_output #(
        .MIX_SHIFT(MIX_SHIFT),
        .SHAPER_ROM_FILE(SHAPER_ROM_FILE)
    ) u_output(
        .clk(clk),
        .rst_n(rst_n),
        .start(output_start),
        .voices_sounding(| voice_active),
        .gain_latched(gain_latched),
        .piano_sum(piano_sum),
        .guitar_sum(guitar_sum),
        .sounding(sounding),
        .sample_data(sample_data),
        .sample_valid(sample_valid),
        .sample_clipped(sample_clipped)
    );
endmodule
