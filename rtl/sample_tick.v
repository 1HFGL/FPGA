// 一个立体声帧依次包含右、左两个时隙。
// 全部状态使用 clk_audio；bclk_half_ce 是单周期时钟使能，不是新时钟。
// 当输入时钟不能整除位时钟时，相位累加器保证长期平均采样率准确，
// 但相邻 BCK 半周期可能相差一个 clk_audio 周期。
module sample_tick #(
    parameter integer AUDIO_CLK_HZ = 25000000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer SLOT_BITS = 16
) (
    input  wire clk_audio,
    input  wire rst_n,
    output wire bclk_half_ce,
    // 每帧右声道时隙开始时置位；同步的样本生成模块在该边沿看到请求。
    output wire frame_start
);

    // 两个声道 × 每声道位数 × 每位两个 BCK 半周期。
    localparam integer HALF_EDGES_PER_FRAME = 4 * SLOT_BITS;
    localparam [31:0] HALF_EDGE_RATE_HZ =
        SAMPLE_RATE_HZ * HALF_EDGES_PER_FRAME;
    localparam [31:0] SOURCE_RATE_HZ = AUDIO_CLK_HZ;

    reg [31:0] phase_acc;
    reg [15:0] half_edge_index;
    wire [32:0] phase_sum = {1'b0, phase_acc} + {1'b0, HALF_EDGE_RATE_HZ};

    // 合法参数：0 < HALF_EDGE_RATE_HZ <= AUDIO_CLK_HZ，
    // AUDIO_CLK_HZ < 2^31，且 4*SLOT_BITS <= 65536。
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
