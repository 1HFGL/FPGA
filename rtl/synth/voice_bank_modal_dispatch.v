// Formal dual-16 engine; historical <=16 contract stays available.
module voice_bank_modal_dispatch #(
    parameter integer VOICES = 16, MIX_SHIFT = 3,
    parameter integer PAIRED = (VOICES > 16),
    parameter [31:0] P_RELEASE = 4096, G_RELEASE = 2048,
    parameter MODE_ROM_FILE = "rtl/rom/piano_v3_modes.mem",
    parameter MODE_EVEN_FILE = "rtl/rom/modes_even.mem",
    parameter MODE_ODD_FILE = "rtl/rom/modes_odd.mem",
    parameter SHAPER_ROM_FILE = "rtl/rom/rock_v2_shaper.mem",
    parameter SINE_ROM_FILE = "rtl/rom/sine_1024.mem"
)(
    input wire clk, rst_n, sample_request,
    input wire [16:0] global_gain_q16, pitch_ratio_q16,
    input wire [VOICES - 1:0] voice_gate, voice_retrigger, voice_instrument,
    input wire [VOICES * 7 - 1:0] voice_note_flat, voice_velocity_flat,
    output wire [VOICES - 1:0] voice_active, release_done,
    output wire [VOICES - 1:0] instrument_active,
    output wire [VOICES * 17 - 1:0] env_level_flat,
    output wire sounding, busy,
    output wire signed [15:0] sample_data,
    output wire sample_valid, sample_clipped, overrun
);
    generate
        if (VOICES == 32) begin : g_dual
            voice_bank_dual16 #(
                .MIX_SHIFT(MIX_SHIFT),
                .P_RELEASE(P_RELEASE),
                .G_RELEASE(G_RELEASE),
                .SHAPER_ROM_FILE(SHAPER_ROM_FILE),
                .SINE_ROM_FILE(SINE_ROM_FILE)
            ) u_engine(
                .clk(clk),
                .rst_n(rst_n),
                .sample_request(sample_request),
                .global_gain_q16(global_gain_q16),
                .pitch_ratio_q16(pitch_ratio_q16),
                .voice_gate(voice_gate),
                .voice_retrigger(voice_retrigger),
                .voice_instrument(voice_instrument),
                .voice_note_flat(voice_note_flat),
                .voice_velocity_flat(voice_velocity_flat),
                .voice_active(voice_active),
                .release_done(release_done),
                .instrument_active(instrument_active),
                .env_level_flat(env_level_flat),
                .sounding(sounding),
                .busy(busy),
                .sample_data(sample_data),
                .sample_valid(sample_valid),
                .sample_clipped(sample_clipped),
                .overrun(overrun)
            );
        end else begin : g_legacy
            voice_bank_music_pipe #(
                .VOICES(VOICES),
                .MIX_SHIFT(MIX_SHIFT),
                .PAIRED(PAIRED),
                .P_RELEASE(P_RELEASE),
                .G_RELEASE(G_RELEASE),
                .MODE_ROM_FILE(MODE_ROM_FILE),
                .MODE_EVEN_FILE(MODE_EVEN_FILE),
                .MODE_ODD_FILE(MODE_ODD_FILE),
                .SHAPER_ROM_FILE(SHAPER_ROM_FILE),
                .SINE_ROM_FILE(SINE_ROM_FILE)
            ) u_engine(
                .clk(clk),
                .rst_n(rst_n),
                .sample_request(sample_request),
                .global_gain_q16(global_gain_q16),
                .pitch_ratio_q16(pitch_ratio_q16),
                .voice_gate(voice_gate),
                .voice_retrigger(voice_retrigger),
                .voice_instrument(voice_instrument),
                .voice_note_flat(voice_note_flat),
                .voice_velocity_flat(voice_velocity_flat),
                .voice_active(voice_active),
                .release_done(release_done),
                .instrument_active(instrument_active),
                .env_level_flat(env_level_flat),
                .sounding(sounding),
                .busy(busy),
                .sample_data(sample_data),
                .sample_valid(sample_valid),
                .sample_clipped(sample_clipped),
                .overrun(overrun)
            );
        end
    endgenerate
    // synthesis translate_off
    // Hierarchical observation for existing tests; unused wires synthesize away.
    wire signed [15:0] last_voice[0:VOICES - 1];
    genvar k;
    generate
        for (k = 0; k < VOICES; k = k + 1) begin : g_observe
            if (VOICES == 32) begin : g_32
                if (k < 16) assign last_voice[k] = g_dual.u_engine.u_group0.last_voice[k];
                else assign last_voice[k] = g_dual.u_engine.u_group1.last_voice[k - 16];
            end else begin : g_other
                assign last_voice[k] = g_legacy.u_engine.last_voice[k];
            end
        end
    endgenerate
    wire [16:0] gain_latched, ratio_latched;
    wire [VOICES * 7 - 1:0] notes;
    generate
        if (VOICES == 32) begin : g_controls32
            assign gain_latched = g_dual.u_engine.gain_latched;
            assign ratio_latched = g_dual.u_engine.u_group0.ratio_latched;
            assign notes = {g_dual.u_engine.u_group1.notes, g_dual.u_engine.u_group0.notes};
        end else begin : g_controls_old
            assign gain_latched = g_legacy.u_engine.gain_latched;
            assign ratio_latched = g_legacy.u_engine.ratio_latched;
            assign notes = g_legacy.u_engine.notes;
        end
    endgenerate
    // synthesis translate_on
endmodule
