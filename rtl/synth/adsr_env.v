`timescale 1ns/1ps

// 单声部线性 ADSR：所有寄存器使用 clk，sample_tick 只作为采样使能。
// env_level 使用无符号 Q1.16：0 表示静音，65536 表示单位增益。
// 本模块只生成“音量系数”，不生成正负摆动的音频波形。
// 按下：IDLE -> ATTACK(渐强) -> DECAY(变轻) -> SUSTAIN(按住保持)。
// 松开：从当时幅度进入RELEASE(淡出) -> IDLE；提前松开不必等A/D结束。
// 状态只在sample_tick有效的上升沿推进，其他clk周期用于保存短触发脉冲。
// retrigger会从当前幅度重新起音，而不是先跳到0；gate=0时松键优先。
module adsr_env #(
    // 参数单位是“采样点”，不是 clk 周期；以下默认值对应 48 kHz。
    parameter [31:0] ATTACK_SAMPLES  = 32'd96,    // 2 ms
    parameter [31:0] DECAY_SAMPLES   = 32'd24000, // 500 ms
    parameter [16:0] SUSTAIN_LEVEL   = 17'd6554,  // 约 10% 峰值幅度
    parameter [31:0] RELEASE_SAMPLES = 32'd5760   // 120 ms
) (
    input  wire        clk,
    input  wire        rst,         // 高有效同步复位，优先于采样/触发
    input  wire        sample_tick, // 即使松键或静音也应继续提供
    input  wire        gate,        // 同步的按住状态；不直接连接物理按键
    input  wire        retrigger,   // 一个 clk 周期的重触发脉冲
    output reg  [16:0] env_level,
    output wire        active,      // 释放阶段结束后才空闲
    output reg  [2:0]  state        // 调试：0空闲/1起音/2衰减/3保持/4释放
);
    localparam [2:0] IDLE=3'd0, ATTACK=3'd1, DECAY=3'd2,
                     SUSTAIN=3'd3, RELEASE=3'd4;
    localparam [16:0] UNITY=17'd65536;
    localparam [16:0] SUSTAIN_CLAMP=(SUSTAIN_LEVEL>UNITY)?UNITY:SUSTAIN_LEVEL;
    // 0 点时长定义为下一个采样立即到终点；用 1 替代也避免除零。
    localparam [31:0] A_N=(ATTACK_SAMPLES==0)?32'd1:ATTACK_SAMPLES;
    localparam [31:0] D_N=(DECAY_SAMPLES==0)?32'd1:DECAY_SAMPLES;
    localparam [31:0] R_N=(RELEASE_SAMPLES==0)?32'd1:RELEASE_SAMPLES;
    localparam [31:0] MAX_AD=(A_N>D_N)?A_N:D_N;
    localparam [31:0] MAX_N=(MAX_AD>R_N)?MAX_AD:R_N;

    // 计数器必须能表示 N 本身；例如 N=256 需要 9 位，不能只表示 N-1。
    // 默认最大时长 24000 只需 15 位，同时保留全部 32 位参数范围。
    function integer count_bits;
        input [31:0] value;
        reg [31:0] shifted;
        begin
            shifted=value;
            count_bits=0;
            while (shifted!=0) begin
                count_bits=count_bits+1;
                shifted=shifted>>1;
            end
            if (count_bits==0) count_bits=1;
        end
    endfunction
    localparam integer COUNT_W=count_bits(MAX_N);

    // gate_sampled记的是“上一次采样时”的gate，不是上一个50MHz周期的gate。
    // pending保存采样间隙出现的触发；多次触发只保留“至少发生一次”。
    reg gate_sampled, retrigger_pending;
    // 每段把总距离分成N份：base_step为整数商，remainder为剩下要分摊的格数。
    // ticks_left记录本段剩余采样次数，error_acc记录尚未凑成额外一步的余数。
    reg [COUNT_W-1:0] ticks_left, remainder, error_acc;
    reg [16:0] base_step;
    reg [2:0] next_state;
    reg [16:0] next_level, next_base;
    reg [COUNT_W-1:0] next_left, next_remainder, next_error;
    reg start_segment;

    // 初始化与正常推进分开计算：第一步的误差从 0 开始，r<N，
    // 必定没有额外进位。因此除法之后无需再串联余数比较和步长加一。
    wire [16:0] attack_distance=UNITY-env_level;
    wire [16:0] attack_step=attack_distance/A_N;
    wire [COUNT_W-1:0] attack_rem=attack_distance%A_N;
    wire [16:0] release_step=env_level/R_N;
    wire [COUNT_W-1:0] release_rem=env_level%R_N;
    // 衰减只能从起音终点进入，起始幅度一定是 UNITY，可在综合期算好。
    localparam [16:0] D_DISTANCE=UNITY-SUSTAIN_CLAMP;
    localparam [16:0] D_STEP=D_DISTANCE/D_N;
    localparam [COUNT_W-1:0] D_REM=D_DISTANCE%D_N;

    // 例：从0到65536用96点，65536=682*96+64；每点至少加682，
    // 累计余数满96再多加1，96点后恰到65536。若只反复加682会少64。
    // 这也是保留余数累加器的原因：慢包络即使商为0仍会逐渐走到终点。
    wire [COUNT_W-1:0] duration=(state==ATTACK)?A_N:
                                        (state==DECAY)?D_N:R_N;
    // 两个小于 N 的误差相加可能超过计数器范围，必须先扩一位。
    wire [COUNT_W:0] error_sum={1'b0,error_acc}+{1'b0,remainder};
    wire extra_step=(error_sum>={1'b0,duration});
    wire [COUNT_W:0] wrapped_error=error_sum-{1'b0,duration};
    // 幅度的基本候选值与余数判断并行计算，再选择是否多走一格。
    wire [16:0] add_base=env_level+base_step;
    wire [16:0] sub_base=env_level-base_step;
    wire [16:0] add_extra=add_base+17'd1;
    wire [16:0] sub_extra=sub_base-17'd1;
    assign active=(state!=IDLE);

    always @* begin
        // 组合块只“算下一步”，不会自己推进状态。先全赋默认值避免产生锁存器；
        // 真正保存next_*的是末尾时序块，且只有sample_tick那拍才保存。
        next_state=state;
        next_level=env_level;
        next_left=ticks_left;
        next_base=base_step;
        next_remainder=remainder;
        next_error=error_acc;
        start_segment=1'b0;

        // 松键优先于重触发；进入释放时才记录当前幅度，不能每拍重启。
        if (!gate) begin
            if (env_level==0) next_state=IDLE;
            else if (state!=RELEASE) begin
                next_state=RELEASE;
                start_segment=1'b1;
            end
        end else if (retrigger || retrigger_pending || !gate_sampled || state==IDLE) begin
            // 重触发从当前幅度重新起音，避免先清零造成跳变。
            next_state=ATTACK;
            start_segment=1'b1;
        end else if (state==DECAY && ticks_left==0) begin
            // 达到峰值的那拍属于起音；下一次采样才做衰减第一步。
            start_segment=1'b1;
        end

        if (start_segment) begin
            case (next_state)
                ATTACK: begin
                    next_base=attack_step;
                    next_remainder=attack_rem;
                    next_error=attack_rem;
                    next_left=A_N-32'd1;
                    next_level=env_level+attack_step;
                    if (A_N==1) begin
                        next_level=UNITY; next_state=DECAY; next_error=0;
                    end
                end
                DECAY: begin
                    next_base=D_STEP;
                    next_remainder=D_REM;
                    next_error=D_REM;
                    next_left=D_N-32'd1;
                    next_level=UNITY-D_STEP;
                    if (D_N==1) begin
                        next_level=SUSTAIN_CLAMP; next_state=SUSTAIN; next_error=0;
                    end
                end
                RELEASE: begin
                    next_base=release_step;
                    next_remainder=release_rem;
                    next_error=release_rem;
                    next_left=R_N-32'd1;
                    next_level=env_level-release_step;
                    if (R_N==1) begin
                        next_level=0; next_state=IDLE; next_error=0;
                    end
                end
                default: begin end
            endcase
        end else if (next_state==ATTACK || next_state==DECAY || next_state==RELEASE) begin
            if (ticks_left<=1) begin
                // 第 N 步明确写终值，并在同一拍切换状态，不延长任何一段。
                next_left=0;
                next_error=0;
                case (next_state)
                    ATTACK: begin next_level=UNITY; next_state=DECAY; end
                    DECAY: begin next_level=SUSTAIN_CLAMP; next_state=SUSTAIN; end
                    RELEASE: begin next_level=0; next_state=IDLE; end
                    default: begin end
                endcase
            end else begin
                next_left=ticks_left-1'b1;
                next_error=extra_step?wrapped_error[COUNT_W-1:0]:error_sum[COUNT_W-1:0];
                if (next_state==ATTACK) next_level=extra_step?add_extra:add_base;
                else next_level=extra_step?sub_extra:sub_base;
            end
        end else begin
            next_level=(next_state==SUSTAIN)?SUSTAIN_CLAMP:17'd0;
            next_left=0;
            next_error=0;
            next_base=0;
            next_remainder=0;
        end
    end

    // 每段 distance=q*N+r。第 k 步累计变化 floor(distance*k/N)，
    // 即使幅度很小或时长大于 65536，也不会因步长取整而提前结束。
    always @(posedge clk) begin
        if (rst) begin
            env_level<=0;
            state<=IDLE;
            ticks_left<=0;
            base_step<=0;
            remainder<=0;
            error_acc<=0;
            gate_sampled<=1'b0;
            retrigger_pending<=1'b0;
        end else if (sample_tick) begin
            env_level<=next_level;
            state<=next_state;
            ticks_left<=next_left;
            base_step<=next_base;
            remainder<=next_remainder;
            error_acc<=next_error;
            gate_sampled<=gate;
            retrigger_pending<=1'b0;
        end else if (retrigger) begin
            // 两次采样之间的单拍触发会保留；多个触发合并成一次。
            retrigger_pending<=1'b1;
        end
    end
endmodule
