`timescale 1ns/1ps
// Implementation verification with existing two board-key pins; not the final 13-key/DAC wiring.
module control_audio_verify_top(
    input wire sys_clk, sys_rst_n,
    input wire [1:0] Key_in,
    output wire [3:0] LEDs
);
    wire rst_n;
    wire signed [15:0] audio;
    wire [15:0] active;
    wire input_fault, serial_audio;
    reset_sync resetter(.clk(sys_clk),.raw_rst_n(sys_rst_n),.rst_n_sync(rst_n));
    audio_system_top #(.VOICES(16)) audio_control(
        .clk(sys_clk),.rst_n(rst_n),.key_n({11'h7ff,Key_in}),.key_velocity_flat({13{7'd100}}),
        .octave_select(2'd1),.sustain_on(1'b0),.source_clear_valid(1'b0),.source_clear_id(5'd0),
        .source_clear_mask(5'd0),.source_clear_ready(),.timbre_key_n(1'b1),
        .pressure_valid(1'b0),.pressure_raw(12'd0),.knob_raw_flat({2{12'hfff}}),.knob_valid(1'b1),
        .expr_valid(1'b0),.expr_source_id(5'd0),.expr_note(7'd0),.expr_pitch_bend(16'd0),
        .expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .test_enable(1'b0),.test_clear(1'b0),.test_voices(6'd0),
        .sample_tick(),.audio_sample(audio),.i2s_bclk(),.i2s_lrck(),.i2s_sdata(serial_audio),
        .voice_active(active),.voice_gate(),.voice_key_down(),.voice_trigger_id_flat(),.input_fault(input_fault),
        .timbre_id(),.knob_value_flat(),.param_ready(),.param_fault(),.voice_count(),.max_voice_count(),
        .release_done(),.test_busy(),.test_done()
    );
    assign LEDs={serial_audio,input_fault,|active,audio[15]};
endmodule
