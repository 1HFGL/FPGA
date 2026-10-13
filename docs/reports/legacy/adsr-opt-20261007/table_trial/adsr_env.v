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

    reg gate_sampled, retrigger_pending;
    reg [COUNT_W-1:0] ticks_left, remainder, error_acc;
    reg [16:0] base_step;
    reg [2:0] next_state;
    reg [16:0] next_level, next_base;
    reg [COUNT_W-1:0] next_left, next_remainder, next_error;
    reg start_segment;

    // 初始化与正常推进分开计算：第一步的误差从 0 开始，r<N，
    // 必定没有额外进位。因此除法之后无需再串联余数比较和步长加一。
    wire [16:0] attack_distance=UNITY-env_level;
    wire [16:0] attack_step, release_step;
    wire [COUNT_W-1:0] attack_rem, release_rem;
    generate
        if (A_N==32'd96) begin : g_attack_96
            // 96=3*32。x=32*h+l，因此 q=h/3，r=32*(h%3)+l。
            // 高12位再拆成两段6位，分别查常数商/余数，只需一次余数进位。
            // 表在展开时计算，不是运行时除法，也不是音频采样波表。
            wire [11:0] high_part=attack_distance[16:5];
            wire [12:0] high_table [0:63]; // (64*h)/3 的11位商、2位余数
            wire [6:0] low_table [0:63];   // l/3 的5位商、2位余数
            genvar a;
            for (a=0;a<64;a=a+1) begin : g_constants
                localparam [10:0] HIGH_Q=(64*a)/3;
                localparam [4:0] LOW_Q=a/3;
                localparam [1:0] REM=a%3;
                assign high_table[a]={HIGH_Q,REM};
                assign low_table[a]={LOW_Q,REM};
            end
            wire [12:0] high_result=high_table[high_part[11:6]];
            wire [6:0] low_result=low_table[high_part[5:0]];
            wire [2:0] remainder_sum={1'b0,high_result[1:0]}+{1'b0,low_result[1:0]};
            wire carry=(remainder_sum>=3'd3);
            wire [2:0] remainder_corrected=carry?(remainder_sum-3'd3):remainder_sum;
            wire [5:0] low_quotient={1'b0,low_result[6:2]}+{5'd0,carry};
            wire [10:0] quotient=high_result[12:2]+{5'd0,low_quotient};
            wire [1:0] remainder_small=remainder_corrected[1:0];
            assign attack_step={6'd0,quotient};
            assign attack_rem={remainder_small,attack_distance[4:0]};
        end else begin : g_attack_generic
            assign attack_step=attack_distance/A_N;
            assign attack_rem=attack_distance%A_N;
        end
        if (R_N==32'd5760) begin : g_release_5760
            // 5760=45*128。高10位 n=32*h+l；l<45，所以只查 h 的32项表。
            // 把 h 部分的余数与 l 相加，最多减一次45，商相应加一。
            wire [9:0] high_part=env_level[16:7];
            wire [10:0] high_table [0:31]; // (32*h)/45 的5位商、6位余数
            genvar r;
            for (r=0;r<32;r=r+1) begin : g_constants
                localparam [4:0] HIGH_Q=(32*r)/45;
                localparam [5:0] REM=(32*r)%45;
                assign high_table[r]={HIGH_Q,REM};
            end
            wire [10:0] high_result=high_table[high_part[9:5]];
            wire [6:0] remainder_sum={1'b0,high_result[5:0]}+{2'd0,high_part[4:0]};
            wire carry=(remainder_sum>=7'd45);
            wire [6:0] remainder_corrected=carry?(remainder_sum-7'd45):remainder_sum;
            wire [4:0] quotient=high_result[10:6]+{4'd0,carry};
            wire [5:0] remainder_small=remainder_corrected[5:0];
            assign release_step={12'd0,quotient};
            assign release_rem={remainder_small,env_level[6:0]};
        end else begin : g_release_generic
            assign release_step=env_level/R_N;
            assign release_rem=env_level%R_N;
        end
    endgenerate
    // 衰减只能从起音终点进入，起始幅度一定是 UNITY，可在综合期算好。
    localparam [16:0] D_DISTANCE=UNITY-SUSTAIN_CLAMP;
    localparam [16:0] D_STEP=D_DISTANCE/D_N;
    localparam [COUNT_W-1:0] D_REM=D_DISTANCE%D_N;

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
