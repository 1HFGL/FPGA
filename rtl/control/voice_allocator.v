`timescale 1ns/1ps

// 声部分配器相当于“安排演奏席位”：输入按下/松开事件，输出每个席位的音符和gate。
// source_id是按键/输入来源，note是音高；二者不同，松键须匹配来源和音符。
// gate=1表示继续按住；active=1表示席位仍占用（含gate=0后的释放尾音）。
// note-off先放下gate，等A返回release_done才正常回收；满员时允许策略性抢占。
// 握手在clk上升沿valid && ready时发生；忙于扫描时ready=0，上游必须保存事件。
// 表情与普通事件同时有效时，普通事件优先。全部输出与clk同域，复位低有效。
module voice_allocator #(
    parameter integer VOICES       = 32,
    parameter integer IDX_WIDTH    = 5,
    parameter integer COUNT_WIDTH  = 6,
    parameter integer TIME_WIDTH   = 32, // 保留旧实例兼容；排序已不再依赖时钟时间戳。
    parameter integer SOURCE_WIDTH = 5,
    parameter integer BEND_WIDTH   = 16,
    parameter integer EXPR_WIDTH   = 8,
    parameter integer MERGE_SAME_NOTE = 1,
    parameter integer ENABLE_CANCEL = 0,
    parameter integer ENABLE_PLAY_CONTROL = 0,
    parameter integer CHECK_RELEASE_ID = 0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire event_valid,
    output wire event_ready,
    input  wire event_type,
    input  wire [SOURCE_WIDTH-1:0] event_source_id,
    input  wire [6:0] event_note,
    input  wire [6:0] event_velocity,
    input  wire [3:0] event_timbre,
    input  wire expr_valid,
    output wire expr_ready,
    input  wire [SOURCE_WIDTH-1:0] expr_source_id,
    input  wire [6:0] expr_note, // 兼容字段；表情只更新当前source_id所属声部。
    input  wire [BEND_WIDTH-1:0] expr_pitch_bend,
    input  wire [EXPR_WIDTH-1:0] expr_aftertouch,
    input  wire [EXPR_WIDTH-1:0] expr_vibrato_depth,
    input  wire [EXPR_WIDTH-1:0] expr_vibrato_rate,
    input  wire [VOICES-1:0] release_done,
    // 仅ENABLE_CANCEL=1启用；IDLE沿valid&&ready原子清指定来源gate。
    // 不清active/包络，真实release_done负责回收。外部仲裁控制采样边界。
    input wire cancel_valid,
    output wire cancel_ready,
    input wire [SOURCE_WIDTH-1:0] cancel_mask,cancel_value,
    output reg  [VOICES-1:0] voice_active,
    output reg  [VOICES-1:0] voice_gate,
    output wire [VOICES*SOURCE_WIDTH-1:0] voice_source_id_flat,
    output wire [VOICES*7-1:0] voice_note_flat,
    output wire [VOICES*7-1:0] voice_velocity_flat,
    output wire [VOICES*4-1:0] voice_timbre_flat,
    output wire [VOICES*BEND_WIDTH-1:0] voice_pitch_bend_flat,
    output wire [VOICES*EXPR_WIDTH-1:0] voice_aftertouch_flat,
    output wire [VOICES*EXPR_WIDTH-1:0] voice_vibrato_depth_flat,
    output wire [VOICES*EXPR_WIDTH-1:0] voice_vibrato_rate_flat,
    output wire [COUNT_WIDTH-1:0] voice_count,
    output reg  [COUNT_WIDTH-1:0] max_voice_count,
    output reg  [31:0] note_on_count,
    output reg  [31:0] note_off_count,
    output reg  [31:0] steal_count,
    output reg  steal_pulse,
    // 成功应用 note-on 后输出一拍；同音重触发及抢占也必须通知包络。
    output reg [VOICES-1:0] voice_trigger,
    input wire sustain_on,
    input wire [VOICES*16-1:0] release_trigger_id_flat,
    output wire [VOICES*16-1:0] voice_trigger_id_flat,
    output reg [VOICES-1:0] voice_key_down
);

    // IDLE锁存一条事件 -> 每拍SCAN一个声部 -> APPLY统一更新。
    // 分多拍搜索可避免一次堆出所有比较/优先选择，但不支持每拍接收一条事件。
    localparam [1:0] S_IDLE      = 2'd0;
    localparam [1:0] S_SCAN      = 2'd1;
    localparam [1:0] S_EXPR_SCAN = 2'd2;
    localparam [1:0] S_APPLY     = 2'd3;

    reg [SOURCE_WIDTH-1:0] source_id_mem [0:VOICES-1];
    reg [6:0] note_mem [0:VOICES-1];
    reg [6:0] velocity_mem [0:VOICES-1];
    reg [3:0] timbre_mem [0:VOICES-1];
    reg [BEND_WIDTH-1:0] pitch_bend_mem [0:VOICES-1];
    reg [EXPR_WIDTH-1:0] aftertouch_mem [0:VOICES-1];
    reg [EXPR_WIDTH-1:0] vibrato_depth_mem [0:VOICES-1];
    reg [EXPR_WIDTH-1:0] vibrato_rate_mem [0:VOICES-1];
    function integer rank_bits;
        input integer count;
        integer value;
        begin
            value=count-1;
            rank_bits=0;
            while(value>0) begin rank_bits=rank_bits+1; value=value>>1; end
            if(rank_bits==0) rank_bits=1;
        end
    endfunction
    localparam integer AGE_WIDTH=rank_bits(VOICES);
    // 所有槽（含空闲槽）保存 0..VOICES-1 的排列：0 最新，数值越大越旧。
    // note-on 将目标移到最前，其前面的槽后移；持续演奏多久都不会回绕。
    // 四声部每槽只需2位，32声部每槽5位；不再需要每拍运行的32位计数器。
    reg [AGE_WIDTH-1:0] age_mem [0:VOICES-1];
    // 从C最新控制成果适配：起音/完成代次必须匹配，旧尾音不能回收新音。
    reg [15:0] trigger_id_mem [0:VOICES-1];
    wire sustain_enabled=(ENABLE_PLAY_CONTROL!=0) && sustain_on;

    reg [1:0] state;
    reg op_expr;
    reg [IDX_WIDTH-1:0] scan_idx;

    reg latched_event_type;
    reg [SOURCE_WIDTH-1:0] latched_source_id;
    reg [6:0] latched_note;
    reg [6:0] latched_velocity;
    reg [3:0] latched_timbre;
    reg [SOURCE_WIDTH-1:0] latched_expr_source_id;
    reg [BEND_WIDTH-1:0] latched_pitch_bend;
    reg [EXPR_WIDTH-1:0] latched_aftertouch;
    reg [EXPR_WIDTH-1:0] latched_vibrato_depth;
    reg [EXPR_WIDTH-1:0] latched_vibrato_rate;

    reg same_source_found;
    reg [IDX_WIDTH-1:0] same_source_idx;
    reg same_note_found;
    reg [IDX_WIDTH-1:0] same_note_idx;
    reg free_found;
    reg [IDX_WIDTH-1:0] free_idx;
    reg release_found;
    reg [IDX_WIDTH-1:0] release_idx;
    reg oldest_found;
    reg [IDX_WIDTH-1:0] oldest_idx;
    reg [AGE_WIDTH-1:0] oldest_age;

    reg off_source_found;
    reg [IDX_WIDTH-1:0] off_source_idx;

    reg expr_source_found;
    reg [IDX_WIDTH-1:0] expr_source_idx;

    reg [IDX_WIDTH-1:0] target_idx;
    reg target_valid;
    reg target_is_same;
    reg target_is_steal;

    integer i;
    integer c;
    reg [COUNT_WIDTH-1:0] active_count;
    reg [IDX_WIDTH-1:0] off_target_idx;
    reg off_target_valid;
    reg [IDX_WIDTH-1:0] expr_target_idx;
    reg expr_target_valid;

    assign voice_count = active_count;
    wire cancel_request=(ENABLE_CANCEL!=0) && cancel_valid;
    assign cancel_ready=(state==S_IDLE);
    assign event_ready = (state == S_IDLE) && !cancel_request;
    assign expr_ready = (state == S_IDLE) && !event_valid && !cancel_request;

    always @* begin
        active_count = {COUNT_WIDTH{1'b0}};
        for (c = 0; c < VOICES; c = c + 1) begin
            active_count = active_count + voice_active[c];
        end
    end

    always @* begin
        target_valid = 1'b0;
        target_is_same = 1'b0;
        target_is_steal = 1'b0;
        target_idx = {IDX_WIDTH{1'b0}};
        // note-on优先级：同来源 -> 同音 -> 空闲 -> 松开中的尾音 -> 最老按住音。
        // 同音可能复用已有席位，因此同音按键数量不能直接当独立复音数。
        if (same_source_found) begin
            target_valid = 1'b1;
            target_is_same = 1'b1;
            target_idx = same_source_idx;
        end else if (MERGE_SAME_NOTE!=0 && same_note_found) begin
            target_valid = 1'b1;
            // 同音复用但所有者已改变，重新初始化表情，不能继承旧来源弯音。
            target_is_same = 1'b0;
            target_idx = same_note_idx;
        end else if (free_found) begin
            target_valid = 1'b1;
            target_idx = free_idx;
        end else if (release_found) begin
            target_valid = 1'b1;
            target_is_steal = (ENABLE_PLAY_CONTROL!=0);
            target_idx = release_idx;
        end else if (oldest_found) begin
            target_valid = 1'b1;
            target_is_steal = 1'b1;
            target_idx = oldest_idx;
        end
    end

    always @* begin
        // note-off 必须同时匹配来源和音符。按音符兜底会让被抢占的旧键
        // 误关另一个来源接管的同音；表情也不得跨来源兜底。
        off_target_valid = off_source_found;
        off_target_idx = off_source_idx;
        expr_target_valid = expr_source_found;
        expr_target_idx = expr_source_idx;
    end

    genvar g;
    generate
        for (g = 0; g < VOICES; g = g + 1) begin : g_flat_out
            // +:为“从低位起取指定宽度”：第g路音符占[g*7 +: 7]。
            // 这些assign只是把数组铺平成接口总线，不额外增加采样延迟。
            assign voice_source_id_flat[g*SOURCE_WIDTH +: SOURCE_WIDTH] = source_id_mem[g];
            assign voice_trigger_id_flat[g*16 +: 16] = trigger_id_mem[g];
            assign voice_note_flat[g*7 +: 7] = note_mem[g];
            assign voice_velocity_flat[g*7 +: 7] = velocity_mem[g];
            assign voice_timbre_flat[g*4 +: 4] = timbre_mem[g];
            assign voice_pitch_bend_flat[g*BEND_WIDTH +: BEND_WIDTH] = pitch_bend_mem[g];
            assign voice_aftertouch_flat[g*EXPR_WIDTH +: EXPR_WIDTH] = aftertouch_mem[g];
            assign voice_vibrato_depth_flat[g*EXPR_WIDTH +: EXPR_WIDTH] = vibrato_depth_mem[g];
            assign voice_vibrato_rate_flat[g*EXPR_WIDTH +: EXPR_WIDTH] = vibrato_rate_mem[g];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            op_expr <= 1'b0;
            scan_idx <= {IDX_WIDTH{1'b0}};
            max_voice_count <= {COUNT_WIDTH{1'b0}};
            note_on_count <= 32'd0;
            note_off_count <= 32'd0;
            steal_count <= 32'd0;
            steal_pulse <= 1'b0;
            voice_trigger <= {VOICES{1'b0}};
            voice_active <= {VOICES{1'b0}};
            voice_gate <= {VOICES{1'b0}};
            voice_key_down <= {VOICES{1'b0}};
            for (i = 0; i < VOICES; i = i + 1) begin
                source_id_mem[i] <= {SOURCE_WIDTH{1'b0}};
                note_mem[i] <= 7'd0;
                velocity_mem[i] <= 7'd0;
                timbre_mem[i] <= 4'd0;
                pitch_bend_mem[i] <= {BEND_WIDTH{1'b0}};
                aftertouch_mem[i] <= {EXPR_WIDTH{1'b0}};
                vibrato_depth_mem[i] <= {EXPR_WIDTH{1'b0}};
                vibrato_rate_mem[i] <= {EXPR_WIDTH{1'b0}};
                age_mem[i] <= i;
                trigger_id_mem[i] <= 16'd0;
            end
        end else begin
            steal_pulse <= 1'b0;
            voice_trigger <= {VOICES{1'b0}};

            for (i = 0; i < VOICES; i = i + 1) begin
                if (voice_active[i] && !voice_gate[i] && release_done[i] &&
                    (!CHECK_RELEASE_ID || release_trigger_id_flat[i*16+:16]==trigger_id_mem[i])) begin
                    voice_active[i] <= 1'b0;
                end
                if(ENABLE_PLAY_CONTROL && !sustain_enabled && !voice_key_down[i])
                    voice_gate[i]<=1'b0;
            end

            if (active_count > max_voice_count) begin
                max_voice_count <= active_count;
            end

            case (state)
                S_IDLE: begin
                    if(cancel_request) begin
                        for(i=0;i<VOICES;i=i+1) begin
                            if((source_id_mem[i] & cancel_mask)==(cancel_value & cancel_mask)) begin
                                voice_gate[i]<=1'b0;
                                voice_key_down[i]<=1'b0;
                            end
                        end
                    end else if (event_valid) begin
                        op_expr <= 1'b0;
                        latched_event_type <= event_type;
                        latched_source_id <= event_source_id;
                        latched_note <= event_note;
                        latched_velocity <= event_velocity;
                        latched_timbre <= event_timbre;
                        scan_idx <= {IDX_WIDTH{1'b0}};
                        same_source_found <= 1'b0;
                        same_note_found <= 1'b0;
                        free_found <= 1'b0;
                        release_found <= 1'b0;
                        oldest_found <= 1'b0;
                        off_source_found <= 1'b0;
                        oldest_age <= {AGE_WIDTH{1'b0}};
                        state <= S_SCAN;
                    end else if (expr_valid) begin
                        op_expr <= 1'b1;
                        latched_expr_source_id <= expr_source_id;
                        latched_pitch_bend <= expr_pitch_bend;
                        latched_aftertouch <= expr_aftertouch;
                        latched_vibrato_depth <= expr_vibrato_depth;
                        latched_vibrato_rate <= expr_vibrato_rate;
                        scan_idx <= {IDX_WIDTH{1'b0}};
                        expr_source_found <= 1'b0;
                        state <= S_EXPR_SCAN;
                    end
                end

                S_SCAN: begin
                    if (voice_active[scan_idx] && (ENABLE_PLAY_CONTROL ? voice_key_down[scan_idx] : voice_gate[scan_idx])) begin
                        if (source_id_mem[scan_idx] == latched_source_id &&
                            (!ENABLE_PLAY_CONTROL || note_mem[scan_idx]==latched_note)) begin
                            same_source_found <= 1'b1;
                            same_source_idx <= scan_idx;
                        end
                        if (note_mem[scan_idx] == latched_note) begin
                            same_note_found <= 1'b1;
                            same_note_idx <= scan_idx;
                            if (source_id_mem[scan_idx] == latched_source_id) begin
                                off_source_found <= 1'b1;
                                off_source_idx <= scan_idx;
                            end
                        end
                    end

                    if (!voice_active[scan_idx] && !free_found) begin
                        free_found <= 1'b1;
                        free_idx <= scan_idx;
                    end

                    if (voice_active[scan_idx] && !(ENABLE_PLAY_CONTROL ? voice_key_down[scan_idx] : voice_gate[scan_idx]) &&
                        (!release_found || (ENABLE_PLAY_CONTROL && age_mem[scan_idx]>age_mem[release_idx]))) begin
                        release_found <= 1'b1;
                        release_idx <= scan_idx;
                    end

                    if (voice_active[scan_idx] && (ENABLE_PLAY_CONTROL ? voice_key_down[scan_idx] : voice_gate[scan_idx])) begin
                        if (!oldest_found || (age_mem[scan_idx] > oldest_age)) begin
                            oldest_found <= 1'b1;
                            oldest_idx <= scan_idx;
                            oldest_age <= age_mem[scan_idx];
                        end
                    end

                    if (scan_idx == VOICES-1) begin
                        state <= S_APPLY;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                    end
                end

                S_EXPR_SCAN: begin
                    if (voice_active[scan_idx] && voice_gate[scan_idx]) begin
                        if (source_id_mem[scan_idx] == latched_expr_source_id) begin
                            expr_source_found <= 1'b1;
                            expr_source_idx <= scan_idx;
                        end
                    end

                    if (scan_idx == VOICES-1) begin
                        state <= S_APPLY;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                    end
                end

                S_APPLY: begin
                    // 本沿修改寄存器，沿后voice_trigger才变高；A在后续上升沿读取。
                    // trigger只持续一拍，gate持续到对应松键；两者不可互换。
                    if (op_expr) begin
                        if (expr_target_valid) begin
                            pitch_bend_mem[expr_target_idx] <= latched_pitch_bend;
                            aftertouch_mem[expr_target_idx] <= latched_aftertouch;
                            vibrato_depth_mem[expr_target_idx] <= latched_vibrato_depth;
                            vibrato_rate_mem[expr_target_idx] <= latched_vibrato_rate;
                        end
                    end else if (latched_event_type) begin
                        if (target_valid) begin
                            voice_trigger[target_idx] <= 1'b1;
                            voice_active[target_idx] <= 1'b1;
                            voice_gate[target_idx] <= 1'b1;
                            voice_key_down[target_idx] <= 1'b1;
                            trigger_id_mem[target_idx] <= trigger_id_mem[target_idx]+16'd1;
                            source_id_mem[target_idx] <= latched_source_id;
                            note_mem[target_idx] <= latched_note;
                            velocity_mem[target_idx] <= latched_velocity;
                            timbre_mem[target_idx] <= latched_timbre;
                            // 空闲槽也参与排列，释放造成空洞时仍能保持唯一先后顺序。
                            for (i = 0; i < VOICES; i = i + 1) begin
                                if (i == target_idx) age_mem[i] <= {AGE_WIDTH{1'b0}};
                                else if (age_mem[i] < age_mem[target_idx])
                                    age_mem[i] <= age_mem[i] + 1'b1;
                            end
                            if (!target_is_same) begin
                                pitch_bend_mem[target_idx] <= {BEND_WIDTH{1'b0}};
                                aftertouch_mem[target_idx] <= {EXPR_WIDTH{1'b0}};
                                vibrato_depth_mem[target_idx] <= {EXPR_WIDTH{1'b0}};
                                vibrato_rate_mem[target_idx] <= {EXPR_WIDTH{1'b0}};
                            end
                            note_on_count <= note_on_count + 1'b1;
                            if (target_is_steal) begin
                                steal_count <= steal_count + 1'b1;
                                steal_pulse <= 1'b1;
                            end
                        end
                    end else begin
                        if (off_target_valid) begin
                            voice_gate[off_target_idx] <= sustain_enabled;
                            voice_key_down[off_target_idx] <= 1'b0;
                            note_off_count <= note_off_count + 1'b1;
                            if (!sustain_enabled && release_done[off_target_idx] &&
                                (!CHECK_RELEASE_ID || release_trigger_id_flat[off_target_idx*16+:16]==trigger_id_mem[off_target_idx])) begin
                                voice_active[off_target_idx] <= 1'b0;
                            end
                        end
                    end

                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
