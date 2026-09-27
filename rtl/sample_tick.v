// Audio timing for one stereo frame: right slot, then left slot.
// All state uses clk_audio. bclk_half_ce is a one-cycle clock enable,
// not a new FPGA clock. The fractional accumulator keeps the *average*
// sample rate exact when AUDIO_CLK_HZ is not an integer multiple of BCLK.
module sample_tick #(
    parameter integer AUDIO_CLK_HZ = 25000000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer SLOT_BITS = 16
) (
    input  wire clk_audio,
    input  wire rst_n,
    output wire bclk_half_ce,
    // High on the half-BCLK enable that starts the right-channel slot.
    // A synchronous sample producer sees this request at that clk edge.
    output wire frame_start
);

    // Two channels * SLOT_BITS bits * two BCLK half-periods per bit.
    localparam integer HALF_EDGES_PER_FRAME = 4 * SLOT_BITS;
    localparam [31:0] HALF_EDGE_RATE_HZ =
        SAMPLE_RATE_HZ * HALF_EDGES_PER_FRAME;
    localparam [31:0] SOURCE_RATE_HZ = AUDIO_CLK_HZ;

    reg [31:0] phase_acc;
    reg [15:0] half_edge_index;
    wire [32:0] phase_sum = {1'b0, phase_acc} + {1'b0, HALF_EDGE_RATE_HZ};

    // Legal configuration: 0 < HALF_EDGE_RATE_HZ <= AUDIO_CLK_HZ,
    // AUDIO_CLK_HZ < 2^32, and 4*SLOT_BITS <= 65536.
    assign bclk_half_ce = rst_n && (phase_sum >= {1'b0, SOURCE_RATE_HZ});
    assign frame_start = bclk_half_ce && (half_edge_index == 16'd0);

    always @(posedge clk_audio or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc       <= 32'd0;
            half_edge_index <= 16'd0;
        end else begin
            if (bclk_half_ce) begin
                phase_acc <= phase_sum[31:0] - SOURCE_RATE_HZ;
                if (half_edge_index == HALF_EDGES_PER_FRAME - 1)
                    half_edge_index <= 16'd0;
                else
                    half_edge_index <= half_edge_index + 16'd1;
            end else begin
                phase_acc <= phase_sum[31:0];
            end
        end
    end

endmodule
