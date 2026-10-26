// 一个立体声帧依次包含右、左两个时隙。
// 全部状态使用 clk_audio；bclk_half_ce 是单周期时钟使能，不是新时钟。
// 当输入时钟不能整除位时钟时，相位累加器保证长期平均采样率准确，
// 但相邻 BCK 半周期可能相差一个 clk_audio 周期。
// 作用：给串行发送器一个“现在该翻转BCK”的使能，并每帧请求一个新样本。
// 板级参数：48000帧/秒 * 2声道 * 16位 = 平均1.536MHz BCK；
// BCK每周期翻转两次，故每秒需3072000次半周期使能。
// 50MHz不能整除3072000：用累加余数分摊成16/17个系统周期，不能只取整数16。
// 这些是基于名义输入频率的数字设计值，尚不是实测采样率/时钟抖动结果。
module sample_tick #(
    parameter integer AUDIO_CLK_HZ = 25000000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer SLOT_BITS = 16,
    // 0沿用帧起点请求；2表示在下一帧前两个半位时钟准备样本。
    parameter integer REQUEST_LEAD_HALF_EDGES = 0
) (
    input  wire clk_audio,
    input  wire rst_n,
    output wire bclk_half_ce,
    // 每帧右声道时隙开始时置位；同步的样本生成模块在该边沿看到请求。
    output wire frame_start,
    output wire sample_prepare
);

    // 两个声道 × 每声道位数 × 每位两个 BCK 半周期。
    localparam integer HALF_EDGES_PER_FRAME = 4 * SLOT_BITS;
    localparam [31:0] HALF_EDGE_RATE_HZ =
        SAMPLE_RATE_HZ * HALF_EDGES_PER_FRAME;
    localparam [31:0] SOURCE_RATE_HZ = AUDIO_CLK_HZ;
    localparam integer REQUEST_EDGE_INDEX = (REQUEST_LEAD_HALF_EDGES==0) ?
        0 : HALF_EDGES_PER_FRAME-REQUEST_LEAD_HALF_EDGES;

    // Verilog-2001常量函数：能表示0..count-1的最小位宽，至少保留1位。
    function integer counter_bits;
        input integer count;
        integer value;
        begin
            value=count-1;
            counter_bits=0;
            while(value>0)begin
                counter_bits=counter_bits+1;
                value=value>>1;
            end
            if(counter_bits<1)counter_bits=1;
        end
    endfunction
    localparam integer PHASE_BITS=counter_bits(AUDIO_CLK_HZ);
    localparam integer EDGE_BITS=counter_bits(HALF_EDGES_PER_FRAME);
    localparam [PHASE_BITS-1:0] PHASE_THRESHOLD=SOURCE_RATE_HZ-HALF_EDGE_RATE_HZ;
    reg [PHASE_BITS-1:0] phase_acc;
    reg [EDGE_BITS-1:0] half_edge_index;
    wire [PHASE_BITS:0] phase_sum = {1'b0, phase_acc} + HALF_EDGE_RATE_HZ;

    // 每拍往“进度桶”加HALF_EDGE_RATE_HZ，达到SOURCE_RATE_HZ就发一次使能，
    // 并保留余数。状态始终满足0<=phase_acc<SOURCE_RATE_HZ，因此
    // phase_acc+RATE>=SOURCE 等价于 phase_acc>=SOURCE-RATE。
    // 直接比较阈值可让高扇出使能绕过加法器；发脉冲时也只需一次减法。
    // 不增加寄存器级数，第一拍和之后所有请求时刻与原累加器一致。
    // 扩展一位保存加法结果；RATE==SOURCE时阈值为0，每拍触发，不走加法支路。
    // 合法参数：0 < HALF_EDGE_RATE_HZ <= AUDIO_CLK_HZ，
    // AUDIO_CLK_HZ < 2^31，且 4*SLOT_BITS <= 65536。
    assign bclk_half_ce = rst_n && (phase_acc >= PHASE_THRESHOLD);
    assign frame_start = bclk_half_ce && (half_edge_index == {EDGE_BITS{1'b0}});
    assign sample_prepare = bclk_half_ce && (half_edge_index == REQUEST_EDGE_INDEX);

    // 仅供验证入口拒绝非法配置；不综合运行期检查硬件。
    // 先以64位计算频率，不能让非法参数乘积先溢出32位再通过检查。
    // synthesis translate_off
    initial begin
        if(AUDIO_CLK_HZ<=0 || SAMPLE_RATE_HZ<=0 || SLOT_BITS<1 || SLOT_BITS>16384 ||
           (64'd4*SLOT_BITS*SAMPLE_RATE_HZ)>AUDIO_CLK_HZ ||
           REQUEST_LEAD_HALF_EDGES<0 || REQUEST_LEAD_HALF_EDGES>=HALF_EDGES_PER_FRAME) begin
            $display("FAIL sample_tick invalid timing parameters"); $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk_audio or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc       <= {PHASE_BITS{1'b0}};
            half_edge_index <= {EDGE_BITS{1'b0}};
        end else begin
            if (bclk_half_ce) begin
                phase_acc <= phase_acc - PHASE_THRESHOLD;
                if (half_edge_index == HALF_EDGES_PER_FRAME - 1)
                    half_edge_index <= {EDGE_BITS{1'b0}};
                else
                    half_edge_index <= half_edge_index + 1'b1;
            end else begin
                // 未触发时相加仍小于SOURCE_RATE_HZ，丢弃最高扩展位不会丢数据。
                phase_acc <= phase_sum[PHASE_BITS-1:0];
            end
        end
    end

endmodule
