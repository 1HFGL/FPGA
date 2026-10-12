`timescale 1ns/1ps

module poly_mixer_saturator #(
    parameter integer VOICES = 32
) (
    input  wire [VOICES*16-1:0] voice_sample_flat,
    output reg  signed [15:0] audio_sample
);

    integer i;
    reg signed [39:0] mix_sum;

    always @* begin
        mix_sum = 40'sd0;
        for (i = 0; i < VOICES; i = i + 1) begin
            mix_sum = mix_sum + $signed(voice_sample_flat[i*16 +: 16]);
        end

        if (mix_sum > 40'sd32767) begin
            audio_sample = 16'sd32767;
        end else if (mix_sum < -40'sd32768) begin
            audio_sample = -16'sd32768;
        end else begin
            audio_sample = mix_sum[15:0];
        end
    end

endmodule