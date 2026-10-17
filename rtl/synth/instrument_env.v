`timescale 1ns/1ps

// 单声部双预设线性 ADSR；事件/预设快照由 voice_instrument 负责。
// 所有寄存器使用 clk，sample_tick 只作为采样使能。
// env_level 使用无符号 Q1.16：0 表示静音，65536 表示单位增益。
module instrument_env #(
    parameter [31:0] G_ATTACK=32'd64, G_DECAY=32'd32768, G_RELEASE=32'd4096,
    parameter [16:0] G_SUSTAIN=17'd0,
    parameter [31:0] S_ATTACK=32'd1024, S_DECAY=32'd8192, S_RELEASE=32'd8192,
    parameter [16:0] S_SUSTAIN=17'd49152
) (
    input  wire        clk,
    input  wire        rst,         // 高有效同步复位，优先于采样/触发
    input  wire        sample_tick, // 即使松键或静音也应继续提供
    input  wire        gate,        // 同步的按住状态；不直接连接物理按键
    input  wire        note_on,     // 上层已合并触发事件，只在请求拍采纳
    input  wire        instrument,  // 0拨弦/1弦乐；起音旁路或已锁存预设
    output reg  [16:0] env_level,
    output wire        active,      // 释放阶段结束后才空闲
    output reg  [2:0]  state        // 调试：0空闲/1起音/2衰减/3保持/4释放
);
    localparam [2:0] IDLE=3'd0, ATTACK=3'd1, DECAY=3'd2,
                     SUSTAIN=3'd3, RELEASE=3'd4;
    localparam [16:0] UNITY=17'd65536;
    localparam [16:0] G_SC=(G_SUSTAIN>UNITY)?UNITY:G_SUSTAIN;
    localparam [16:0] S_SC=(S_SUSTAIN>UNITY)?UNITY:S_SUSTAIN;
    localparam [31:0] G_AN=(G_ATTACK==0)?1:G_ATTACK, G_DN=(G_DECAY==0)?1:G_DECAY,
                      G_RN=(G_RELEASE==0)?1:G_RELEASE;
    localparam [31:0] S_AN=(S_ATTACK==0)?1:S_ATTACK, S_DN=(S_DECAY==0)?1:S_DECAY,
                      S_RN=(S_RELEASE==0)?1:S_RELEASE;
    localparam [31:0] G_AD=(G_AN>G_DN)?G_AN:G_DN, S_AD=(S_AN>S_DN)?S_AN:S_DN;
    localparam [31:0] G_MAX=(G_AD>G_RN)?G_AD:G_RN, S_MAX=(S_AD>S_RN)?S_AD:S_RN;
    localparam [31:0] MAX_N=(G_MAX>S_MAX)?G_MAX:S_MAX;
    wire [16:0] SUSTAIN_CLAMP=instrument?S_SC:G_SC;
    wire [31:0] A_N=instrument?S_AN:G_AN, D_N=instrument?S_DN:G_DN,
                R_N=instrument?S_RN:G_RN;

    // 计数器必须能表示 N 本身；例如 N=256 需要 9 位，不能只表示 N-1。
    // 默认最大时长 32768 需要 16 位，同时保留全部 32 位参数范围。
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
    // COUNT_W 按六个时长的最大值计算，截取只去掉必为0的高位。
    wire [COUNT_W-1:0] A_COUNT=A_N[COUNT_W-1:0],
                       D_COUNT=D_N[COUNT_W-1:0], R_COUNT=R_N[COUNT_W-1:0];

    reg [COUNT_W-1:0] ticks_left, remainder, error_acc;
    reg [16:0] base_step;
    reg [2:0] next_state;
    reg [16:0] next_level, next_base;
    reg [COUNT_W-1:0] next_left, next_remainder, next_error;
    reg start_segment;

    // 初始化与正常推进分开计算：第一步的误差从 0 开始，r<N，
    // 必定没有额外进位。因此除法之后无需再串联余数比较和步长加一。
    // 起音预设可在接受请求的同一拍改变，sample_tick 也允许连续有效。
    // 因此不能缓存上一拍按 instrument 选出的步长，否则会使用旧预设/旧幅度。
    // 两套常量除法与首步幅度并行计算，最后再选预设；不增加采样延迟。
    wire [16:0] attack_distance=UNITY-env_level;
    wire [16:0] g_attack_step=attack_distance/G_AN, s_attack_step=attack_distance/S_AN;
    wire [16:0] g_release_step=env_level/G_RN, s_release_step=env_level/S_RN;
    wire [16:0] attack_step=instrument?s_attack_step:g_attack_step;
    wire [16:0] release_step=instrument?s_release_step:g_release_step;
    wire [COUNT_W-1:0] attack_rem=instrument?(attack_distance%S_AN):(attack_distance%G_AN);
    wire [COUNT_W-1:0] release_rem=instrument?(env_level%S_RN):(env_level%G_RN);
    // 每个候选都在0..UNITY内，17位足够；加减放在预设选择之前，缩短选择链。
    wire [16:0] g_attack_first=env_level+g_attack_step, s_attack_first=env_level+s_attack_step;
    wire [16:0] g_release_first=env_level-g_release_step, s_release_first=env_level-s_release_step;
    wire [16:0] attack_first_level=instrument?s_attack_first:g_attack_first;
    wire [16:0] release_first_level=instrument?s_release_first:g_release_first;
    // 衰减只能从起音终点进入，起始幅度一定是 UNITY，可在综合期算好。
    // 两套常量分别除后再选择，避免运行时可变除法器。
    localparam [16:0] G_DISTANCE=UNITY-G_SC, S_DISTANCE=UNITY-S_SC;
    wire [16:0] D_STEP=instrument?(S_DISTANCE/S_DN):(G_DISTANCE/G_DN);
    wire [COUNT_W-1:0] D_REM=instrument?(S_DISTANCE%S_DN):(G_DISTANCE%G_DN);

    wire [COUNT_W-1:0] duration=(state==ATTACK)?A_COUNT:
                                        (state==DECAY)?D_COUNT:R_COUNT;
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
        end else if (note_on) begin
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
                    next_left=A_COUNT-1'b1;
                    next_level=attack_first_level;
                    if (A_N==1) begin
                        next_level=UNITY; next_state=DECAY; next_error=0;
                    end
                end
                DECAY: begin
                    next_base=D_STEP;
                    next_remainder=D_REM;
                    next_error=D_REM;
                    next_left=D_COUNT-1'b1;
                    next_level=UNITY-D_STEP;
                    if (D_N==1) begin
                        next_level=SUSTAIN_CLAMP; next_state=SUSTAIN; next_error=0;
                    end
                end
                RELEASE: begin
                    next_base=release_step;
                    next_remainder=release_rem;
                    next_error=release_rem;
                    next_left=R_COUNT-1'b1;
                    next_level=release_first_level;
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
        end else if (sample_tick) begin
            env_level<=next_level;
            state<=next_state;
            ticks_left<=next_left;
            base_step<=next_base;
            remainder<=next_remainder;
            error_acc<=next_error;
        end
    end
endmodule
