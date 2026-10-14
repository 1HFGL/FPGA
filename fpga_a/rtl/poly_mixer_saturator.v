`timescale 1ns/1ps

module poly_mixer_saturator #(
    parameter integer VOICES = 32
) (
    input  wire [VOICES*16-1:0] voice_sample_flat,
    output reg  signed [15:0] audio_sample
);

    // A balanced tree avoids a VOICES-deep chain of wide carry adders.
    // Padding also supports non-power-of-two voice counts without extra latency.
    localparam integer LEVELS = (VOICES > 1) ? $clog2(VOICES) : 0;
    localparam integer LEAVES = 1 << LEVELS;
    localparam integer SUM_WIDTH = 16 + LEVELS;
    wire signed [SUM_WIDTH-1:0] sum_tree [1:2*LEAVES-1];
    wire signed [SUM_WIDTH-1:0] mix_sum = sum_tree[1];
    genvar leaf, node;
    generate
        for (leaf = 0; leaf < LEAVES; leaf = leaf + 1) begin : inputs_tree
            if (leaf < VOICES) begin : voice_input
                assign sum_tree[LEAVES+leaf] =
                    {{LEVELS{voice_sample_flat[leaf*16+15]}}, voice_sample_flat[leaf*16 +: 16]};
            end else begin : zero_input
                assign sum_tree[LEAVES+leaf] = {SUM_WIDTH{1'b0}};
            end
        end
        for (node = 1; node < LEAVES; node = node + 1) begin : add_tree
            assign sum_tree[node] = sum_tree[2*node] + sum_tree[2*node+1];
        end
    endgenerate

    always @* begin
        if (mix_sum > 40'sd32767) begin
            audio_sample = 16'sd32767;
        end else if (mix_sum < -40'sd32768) begin
            audio_sample = -16'sd32768;
        end else begin
            audio_sample = mix_sum[15:0];
        end
    end

endmodule
