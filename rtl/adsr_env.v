`timescale 1ns/1ps

// 单声部线性 ADSR：所有寄存器使用 clk，sample_tick 只作为采样使能。
// env_level 使用无符号 Q1.16：0 表示静音，65536 表示单位增益。
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
    // 0 点时长定义为下一个采样立即到终点，仍至少输出一个采样值。
    // 用 1 替代 0 也避免综合时发生除零。
    localparam [31:0] A_N=(ATTACK_SAMPLES==0)?32'd1:ATTACK_SAMPLES;
    localparam [31:0] D_N=(DECAY_SAMPLES==0)?32'd1:DECAY_SAMPLES;
    localparam [31:0] R_N=(RELEASE_SAMPLES==0)?32'd1:RELEASE_SAMPLES;

    reg gate_sampled, retrigger_pending;
    reg [31:0] ticks_left;
    reg [16:0] base_step;
    reg [31:0] remainder, error_acc;

    reg [2:0] next_state;
    reg [16:0] next_level, next_base;
    reg [31:0] next_left, next_remainder, next_error;
    reg start_segment;
    reg [16:0] distance, step_now;
    reg [31:0] duration, left_now, rem_now, err_now;
    reg [32:0] error_sum;
    reg [17:0] level_math;
    assign active=(state!=IDLE);

    always @* begin
        next_state=state;
        next_level=env_level;
        next_left=ticks_left;
        next_base=base_step;
        next_remainder=remainder;
        next_error=error_acc;
        start_segment=1'b0;
        distance=0;
        duration=1;
        left_now=ticks_left;
        step_now=base_step;
        rem_now=remainder;
        err_now=error_acc;
        error_sum=0;
        level_math={1'b0,env_level};

        // 松键优先于重触发；只在进入释放时取当前音量，不能每拍重启释放。
        if (!gate) begin
            if (env_level==0) next_state=IDLE;
            else if (state!=RELEASE) begin
                next_state=RELEASE;
                start_segment=1'b1;
            end
        end else if (retrigger || retrigger_pending || !gate_sampled || state==IDLE) begin
            // 重触发从当前音量重新起音，避免先清零造成幅度跳变。
            next_state=ATTACK;
            start_segment=1'b1;
        end else if (state==DECAY && ticks_left==0) begin
            // 达到峰值的那拍属于起音；下一次采样才做衰减的第一步。
            start_segment=1'b1;
        end

        // 每段距离 distance 分成 N 步：基本步长 q=distance/N，余数 r。
        // 每步累加 r，累计到 N 时多走 1 个幅度单位，余数不会丢失。
        // 第 k 步累计变化 floor(distance*k/N)，因此第 N 步精确到终点。
        // 三处除数都是综合期常量，不使用运行时可变除数。
        case (next_state)
            ATTACK: begin
                duration=A_N;
                if (start_segment) begin
                    distance=UNITY-env_level;
                    step_now=distance/A_N;
                    rem_now=distance%A_N;
                end
            end
            DECAY: begin
                duration=D_N;
                if (start_segment) begin
                    distance=env_level-SUSTAIN_CLAMP;
                    step_now=distance/D_N;
                    rem_now=distance%D_N;
                end
            end
            RELEASE: begin
                duration=R_N;
                if (start_segment) begin
                    distance=env_level;
                    step_now=distance/R_N;
                    rem_now=distance%R_N;
                end
            end
            default: begin end
        endcase

        if (next_state==ATTACK || next_state==DECAY || next_state==RELEASE) begin
            if (start_segment) begin
                left_now=duration;
                err_now=0;
                next_base=step_now;
                next_remainder=rem_now;
            end
            if (left_now<=1) begin
                // 最后一步明确写终值：消除量化残余，并在同拍转换状态。
                next_left=0;
                next_error=0;
                case (next_state)
                    ATTACK: begin next_level=UNITY; next_state=DECAY; end
                    DECAY: begin next_level=SUSTAIN_CLAMP; next_state=SUSTAIN; end
                    RELEASE: begin next_level=0; next_state=IDLE; end
                    default: begin end
                endcase
            end else begin
                next_left=left_now-1'b1;
                // 两个余数相加最多需要 33 位，先扩位再比较/减法。
                error_sum={1'b0,err_now}+{1'b0,rem_now};
                if (error_sum>={1'b0,duration}) begin
                    error_sum=error_sum-{1'b0,duration};
                    step_now=step_now+1'b1;
                end
                next_error=error_sum[31:0];
                if (next_state==ATTACK)
                    level_math={1'b0,env_level}+{1'b0,step_now};
                else
                    level_math={1'b0,env_level}-{1'b0,step_now};
                next_level=level_math[16:0];
            end
        end else begin
            next_level=(next_state==SUSTAIN)?SUSTAIN_CLAMP:17'd0;
            next_left=0;
            next_error=0;
            next_base=0;
            next_remainder=0;
        end
    end

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
            // 两个采样之间的单拍触发会保留；多个触发合并成一次。
            retrigger_pending<=1'b1;
        end
    end
endmodule
