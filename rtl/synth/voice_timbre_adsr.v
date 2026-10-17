`timescale 1ns/1ps

// 两音色单声部。DDS/ADSR 在请求 R0 更新，乘法结果在 R1 输出；
// 与原 voice_adsr 延迟一致。相位不因换音色/重触发而强行归零。
// ENABLE_GUITAR=1时复用拨弦引擎：0钢琴/1吉他；多一拍亮度流水线，R2输出。
module voice_timbre_adsr #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem",
    parameter BRIGHT_ROM_FILE = "rtl/rom/bright_1024.mem",
    parameter [31:0] ATTACK_SAMPLES = 32'd96,
    parameter [31:0] DECAY_SAMPLES = 32'd24000,
    parameter [16:0] SUSTAIN_LEVEL = 17'd6554,
    parameter [31:0] RELEASE_SAMPLES = 32'd5760,
    parameter integer ENABLE_GUITAR=0,
    parameter GUITAR_ROM_FILE="rtl/rom/guitar_1024.mem",
    parameter SINE_ROM_FILE="rtl/rom/sine_1024.mem"
) (
    input wire clk, rst, sample_tick,
    input wire [31:0] phase_inc,
    input wire gate, retrigger,
    input wire timbre, // 新音符/重新触发所选音色；保持和尾音期间改变无效
    output wire signed [15:0] sample,
    output wire sample_valid,
    output wire [16:0] env_level,
    output wire voice_active
);
    wire [31:0] phase;
    wire [9:0] addr;
    wire signed [15:0] raw_sample;
    wire raw_valid, env_active;
    wire signed [15:0] legacy_sample;
    wire legacy_valid;
    wire [16:0] legacy_env_level;
    wire [2:0] env_state;
    reg gate_sampled, retrigger_pending, pending_timbre, active_timbre;

    // 与 adsr_env 的起音事件完全对齐，用请求前的状态判断。
    // 不能等待 state==ATTACK 才选音色：0/1 点起音会直接到 DECAY。
    wire start_note = sample_tick && gate &&
        (retrigger || retrigger_pending || !gate_sampled || !env_active);
    // 同拍触发优先，其次使用两请求之间已快照的最新触发，再是自然起音。
    wire event_timbre = retrigger ? timbre :
                         (retrigger_pending ? pending_timbre : timbre);
    // 同拍旁路使起音的第一个样本立即采用新色，不多加流水线级。
    wire requested_timbre = start_note ? event_timbre : active_timbre;
    // 明亮表最高为四次谐波；4*f 必须小于 Fs/2，即 phase_inc < 2^29。
    // 48 kHz 时阈值为 6 kHz；高音退回正弦，保留音高和相位连续性。
    wire read_bright = requested_timbre && (phase_inc < 32'h20000000);

    always @(posedge clk) begin
        if (rst) begin
            gate_sampled <= 1'b0;
            retrigger_pending <= 1'b0;
            pending_timbre <= 1'b0;
            active_timbre <= 1'b0;
        end else if (sample_tick) begin
            gate_sampled <= gate;
            retrigger_pending <= 1'b0;
            if (start_note) active_timbre <= event_timbre;
            // gate=0 时请求只推进尾音，丢弃暂存触发且保留原音色。
        end else if (retrigger) begin
            retrigger_pending <= 1'b1;
            pending_timbre <= timbre; // 多个触发合并，最新事件的音色获胜
        end
    end

    phase_acc u_phase_acc (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .phase_inc(phase_inc), .phase(phase), .wave_addr(addr)
    );
    wave_lut_timbre #(.ROM_FILE(ROM_FILE), .BRIGHT_ROM_FILE(BRIGHT_ROM_FILE)) u_wave (
        .clk(clk), .rst(rst), .read_en(sample_tick), .addr(addr),
        .timbre(read_bright), .sample(raw_sample), .sample_valid(raw_valid)
    );
    adsr_env #(
        .ATTACK_SAMPLES(ATTACK_SAMPLES), .DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .RELEASE_SAMPLES(RELEASE_SAMPLES)
    ) u_env (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .gate(gate),
        .retrigger(retrigger), .env_level(legacy_env_level), .active(env_active), .state(env_state)
    );
    // 保留默认入口的层次/时序，正式双音色入口由常量参数选择，综合裁剪未用路径。
    sample_gain u_gain (
        .clk(clk), .rst(rst), .in_valid(raw_valid), .sample_in(raw_sample),
        .gain(legacy_env_level), .sample_out(legacy_sample), .out_valid(legacy_valid)
    );
    wire signed [15:0] dual_sample;
    wire dual_valid,dual_active;
    wire [16:0] dual_env;
    generate if(ENABLE_GUITAR)begin:g_dual
        // 复用A的拨弦亮度变化；第二预设用原钢琴表和包络，不复制声部池。
        // A接口0=吉他/1=第二预设，外部接口0=钢琴/1=吉他，因此取反。
        voice_instrument #(.SINE_ROM_FILE(SINE_ROM_FILE),.GUITAR_ROM_FILE(GUITAR_ROM_FILE),
            .STRINGS_ROM_FILE(ROM_FILE),.S_FIXED_TONE(1),
            .S_ATTACK(ATTACK_SAMPLES),.S_DECAY(DECAY_SAMPLES),
            .S_SUSTAIN(SUSTAIN_LEVEL),.S_RELEASE(RELEASE_SAMPLES)) u_instrument(
            .clk(clk),.rst(rst),.sample_tick(sample_tick),.phase_inc(phase_inc),
            .gate(gate),.retrigger(retrigger),.instrument(~timbre),
            .sample(dual_sample),.sample_valid(dual_valid),.env_level(dual_env),
            .tone_level(),.voice_active(dual_active),.active_instrument());
    end else begin:g_no_dual
        assign dual_sample=0;assign dual_valid=0;assign dual_env=0;assign dual_active=0;
    end endgenerate
    assign sample=ENABLE_GUITAR?dual_sample:legacy_sample;
    assign sample_valid=ENABLE_GUITAR?dual_valid:legacy_valid;
    assign env_level=ENABLE_GUITAR?dual_env:legacy_env_level;
    assign voice_active=ENABLE_GUITAR?dual_active:(env_active | (legacy_valid && legacy_sample!=16'sd0));
endmodule
