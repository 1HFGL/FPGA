// PT8211-S transmitter: 16-bit LSB-justified (Japanese), not Philips I2S.
// WS=0 right, WS=1 left. WS/DIN change on falling BCK; DAC samples on rising.
// For this board, SAMPLE_BITS and SLOT_BITS must both be 16.
module i2s_tx #(
    parameter integer SAMPLE_BITS = 16,
    parameter integer SLOT_BITS = 16
) (
    input  wire clk_audio,
    input  wire rst_n,
    input  wire bclk_half_ce,
    input  wire frame_start,
    // A valid on frame_start is queued for the following frame.
    input  wire signed [SAMPLE_BITS-1:0] sample_data,
    input  wire sample_valid,
    output reg  i2s_bclk,
    output reg  i2s_lrclk,
    output reg  i2s_sdata,
    output reg  sample_underrun
);

    reg [SAMPLE_BITS-1:0] pending_sample;
    reg pending_valid;
    reg [SAMPLE_BITS-1:0] active_sample;
    reg [SAMPLE_BITS-1:0] shift_reg;
    reg [15:0] bit_index;
    wire [SAMPLE_BITS-1:0] next_sample =
        pending_valid ? pending_sample : {SAMPLE_BITS{1'b0}};

    // One-frame buffer: the latest valid sample before a frame boundary wins.
    // Missing input inserts digital zero and records an underrun for that frame.
    always @(posedge clk_audio or negedge rst_n) begin
        if (!rst_n) begin
            pending_sample  <= {SAMPLE_BITS{1'b0}};
            pending_valid   <= 1'b0;
            active_sample   <= {SAMPLE_BITS{1'b0}};
            shift_reg       <= {SAMPLE_BITS{1'b0}};
            bit_index       <= 16'd0;
            i2s_bclk        <= 1'b1; // first frame_start is a falling edge
            i2s_lrclk       <= 1'b1;
            i2s_sdata       <= 1'b0;
            sample_underrun <= 1'b0;
        end else begin
            if (sample_valid)
                pending_sample <= sample_data;
            if (bclk_half_ce && frame_start)
                pending_valid <= sample_valid;
            else if (sample_valid)
                pending_valid <= 1'b1;

            if (bclk_half_ce) begin
                if (frame_start) begin
                    // Use OLD pending_valid; a concurrent valid is for next frame.
                    active_sample   <= next_sample;
                    shift_reg       <= next_sample;
                    bit_index       <= 16'd0;
                    i2s_bclk        <= 1'b0;
                    i2s_lrclk       <= 1'b0;
                    i2s_sdata       <= next_sample[SAMPLE_BITS-1];
                    sample_underrun <= !pending_valid;
                end else if (i2s_bclk) begin
                    // Falling BCK: set up the following data bit.
                    i2s_bclk <= 1'b0;
                    if (bit_index == SLOT_BITS - 1) begin
                        bit_index <= 16'd0;
                        i2s_lrclk <= ~i2s_lrclk;
                        shift_reg <= active_sample;
                        i2s_sdata <= active_sample[SAMPLE_BITS-1];
                    end else begin
                        bit_index <= bit_index + 16'd1;
                        shift_reg <= {shift_reg[SAMPLE_BITS-2:0], 1'b0};
                        i2s_sdata <= shift_reg[SAMPLE_BITS-2];
                    end
                end else begin
                    // Rising BCK: hold WS and DIN stable for the DAC.
                    i2s_bclk <= 1'b1;
                end
            end
        end
    end

endmodule
