// 板载 PT8211-S 的串行发送器：16 位 LSBJ（右对齐）格式，不是标准 I2S 的一位延迟格式。
// WS=0 对应右声道，WS=1 对应左声道；在 BCK 下降沿更新 WS/DIN，DAC 在上升沿采样。
// 当前板卡实现只支持 SAMPLE_BITS == SLOT_BITS == 16。
module i2s_tx #(
    parameter integer SAMPLE_BITS = 16,
    parameter integer SLOT_BITS = 16
) (
    input  wire clk_audio,
    input  wire rst_n,
    input  wire bclk_half_ce,
    input  wire frame_start,
    // 与 clk_audio 同步；在 frame_start 同周期送来的样本属于下一帧。
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

    // 单帧缓冲：帧边界之前最后一个有效样本生效。
    // 若本帧没有收到新样本，则发送数字零，并记录本帧欠载。
    always @(posedge clk_audio or negedge rst_n) begin
        if (!rst_n) begin
            pending_sample  <= {SAMPLE_BITS{1'b0}};
            pending_valid   <= 1'b0;
            active_sample   <= {SAMPLE_BITS{1'b0}};
            shift_reg       <= {SAMPLE_BITS{1'b0}};
            bit_index       <= 16'd0;
            i2s_bclk        <= 1'b1; // 首个 frame_start 产生下降沿
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
                    // 使用旧的 pending_valid；同周期输入留给下一帧。
                    active_sample   <= next_sample;
                    shift_reg       <= next_sample;
                    bit_index       <= 16'd0;
                    i2s_bclk        <= 1'b0;
                    i2s_lrclk       <= 1'b0;
                    i2s_sdata       <= next_sample[SAMPLE_BITS-1];
                    sample_underrun <= !pending_valid;
                end else if (i2s_bclk) begin
                    // BCK 下降沿：提前准备下一位数据。
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
                    // BCK 上升沿：保持 WS 和 DIN 稳定，供 DAC 采样。
                    i2s_bclk <= 1'b1;
                end
            end
        end
    end

endmodule
