// 四声部集成：所有逻辑都在 clk 域，sample_request 只是使能，不是时钟。
// 请求 R0：DDS 查旧相位；快照力度并更新包络。
// R1：样本 * 包络 * 力度；R2：混音输出且 sample_valid=1。
// B 在 R3 缓存，下一个帧边界发送。请求之间至少间隔 4 个时钟。
module demo_voice_bank (
    input wire clk,
    input wire rst_n,
    input wire sample_request,
    input wire [3:0] voice_gate,
    input wire [27:0] voice_note_flat,
    input wire [27:0] voice_velocity_flat,
    output wire [3:0] release_done,
    output wire sounding,
    output reg signed [15:0] sample_data,
    output reg sample_valid
);
    wire signed [15:0] scaled [0:3];
    wire [3:0] dds_valid;
    wire [3:0] env_nonzero;
    genvar v;
    generate for (v=0; v<4; v=v+1) begin: g_voice
        wire [31:0] phase_inc;
        wire signed [15:0] raw_sample;
        reg [7:0] envelope;
        reg [6:0] velocity;
        // 8*7 位无符号增益，最大 255*127=32385；补零后转正有符号数。
        wire [14:0] gain = envelope * velocity;
        wire signed [15:0] signed_gain = $signed({1'b0, gain});
        reg signed [31:0] product;
        wire signed [31:0] rescaled = product >>> 15;
        assign scaled[v] = rescaled[15:0]; // 范围 [-32385,32384]，不会溢出。
        assign env_nonzero[v] = |envelope;
        assign release_done[v] = !voice_gate[v] && !env_nonzero[v];
        note_phase_lut u_note (.note(voice_note_flat[v*7 +: 7]), .phase_inc(phase_inc));
        voice_dds u_dds (
            .clk(clk), .rst(~rst_n), .sample_tick(sample_request),
            .phase_inc(phase_inc), .sample(raw_sample), .sample_valid(dds_valid[v])
        );
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                envelope <= 8'd0;
                velocity <= 7'd0;
                product <= 32'sd0;
            end else begin
                if (sample_request) begin
                    velocity <= voice_velocity_flat[v*7 +: 7];
                    if (voice_gate[v])
                        envelope <= (envelope >= 8'd247) ? 8'd255 : envelope + 8'd8;
                    else
                        envelope <= (envelope <= 8'd4) ? 8'd0 : envelope - 8'd4;
                end
                if (dds_valid[v]) product <= raw_sample * signed_gain;
            end
        end
    end endgenerate

    // 四个 16 位有符号数显式扩到 18 位求和；总增益 /32。
    // 负数算术移位向负无穷取整，输出范围约 +/-4049，保留低音量余量。
    wire signed [17:0] sum =
        $signed({{2{scaled[0][15]}},scaled[0]}) +
        $signed({{2{scaled[1][15]}},scaled[1]}) +
        $signed({{2{scaled[2][15]}},scaled[2]}) +
        $signed({{2{scaled[3][15]}},scaled[3]});
    wire signed [17:0] quiet_sum = sum >>> 5;
    reg mix_valid;
    assign sounding = (|voice_gate) | (|env_nonzero);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mix_valid <= 1'b0;
            sample_valid <= 1'b0;
            sample_data <= 16'sd0;
        end else begin
            mix_valid <= &dds_valid;
            sample_valid <= mix_valid;
            if (mix_valid) sample_data <= quiet_sum[15:0];
        end
    end
endmodule
