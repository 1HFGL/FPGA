// 四声部 ADSR 集成。复用队友的 voice_adsr，不修改其包络数值规则。
// 请求 R0 -> 包络乘法 R1 -> 力度乘法 R2 -> 混音有效 R3 -> B 在 R4 接收。
// 力度另延迟两拍以对齐；板级请求相隔 1041/1042 拍，远大于四拍流水线。
module adsr_voice_bank #(
    parameter [31:0] ATTACK_SAMPLES = 32'd96,
    parameter [31:0] DECAY_SAMPLES = 32'd24000,
    parameter [16:0] SUSTAIN_LEVEL = 17'd6554,
    parameter [31:0] RELEASE_SAMPLES = 32'd5760
) (
    input wire clk,
    input wire rst_n,
    input wire sample_request,
    input wire [3:0] voice_gate,
    input wire [3:0] voice_trigger,
    input wire [27:0] voice_note_flat,
    input wire [27:0] voice_velocity_flat,
    output wire [3:0] release_done,
    output wire sounding,
    output reg signed [15:0] sample_data,
    output reg sample_valid,
    output wire [67:0] env_level_flat
);
    wire [3:0] core_valid, core_active;
    wire signed [15:0] scaled [0:3];
    reg request_d, velocity_valid;
    reg [3:0] release_idle;
    genvar v;
    generate for (v=0; v<4; v=v+1) begin: g_voice
        wire [31:0] phase_inc;
        wire signed [15:0] core_sample;
        reg [6:0] velocity_r0, velocity_r1;
        reg signed [23:0] product;
        // 固定力度按 velocity/128 缩放；127 是 127/128，不冒称单位增益。
        wire signed [7:0] positive_velocity = $signed({1'b0,velocity_r1});
        wire signed [23:0] rescaled = product >>> 7;
        assign scaled[v] = rescaled[15:0]; // [-32512,32511]，不存在溢出截断。
        assign release_done[v] = !voice_gate[v] && release_idle[v];
        note_phase_lut u_note(.note(voice_note_flat[v*7 +: 7]), .phase_inc(phase_inc));
        voice_adsr #(
            .ATTACK_SAMPLES(ATTACK_SAMPLES), .DECAY_SAMPLES(DECAY_SAMPLES),
            .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .RELEASE_SAMPLES(RELEASE_SAMPLES)
        ) u_voice (
            .clk(clk), .rst(~rst_n), .sample_tick(sample_request),
            .phase_inc(phase_inc), .gate(voice_gate[v]), .retrigger(voice_trigger[v]),
            .sample(core_sample), .sample_valid(core_valid[v]),
            .env_level(env_level_flat[v*17 +: 17]), .voice_active(core_active[v])
        );
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                velocity_r0 <= 0;
                velocity_r1 <= 0;
                product <= 0;
            end else begin
                if (sample_request) velocity_r0 <= voice_velocity_flat[v*7 +: 7];
                if (request_d) velocity_r1 <= velocity_r0;
                if (core_valid[v]) product <= $signed(core_sample) * positive_velocity;
            end
        end
    end endgenerate

    wire signed [17:0] sum =
        $signed({{2{scaled[0][15]}},scaled[0]}) +
        $signed({{2{scaled[1][15]}},scaled[1]}) +
        $signed({{2{scaled[2][15]}},scaled[2]}) +
        $signed({{2{scaled[3][15]}},scaled[3]});
    // 继续保留 /32 的低音量试听余量；理论范围 [-4064,4063]。
    wire signed [17:0] quiet_sum = sum >>> 5;
    assign sounding = (|voice_gate) | (|core_active) | (|(~release_idle));
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request_d <= 0;
            velocity_valid <= 0;
            sample_valid <= 0;
            sample_data <= 0;
            release_idle <= 4'b1111;
        end else begin
            request_d <= sample_request;
            velocity_valid <= &core_valid;
            sample_valid <= velocity_valid;
            if (velocity_valid) begin
                sample_data <= quiet_sum[15:0];
                // 到混音拍再回收：不能只看 gate，不能提前截断释放流水线。
                for (i=0; i<4; i=i+1)
                    release_idle[i] <= !voice_gate[i] && !core_active[i] && (scaled[i]==0);
            end
        end
    end
endmodule
