// 16份独立包络状态，共用一套状态转移逻辑；50MHz单时钟。
// start在R0采纳整组输入：R1更新槽0，R16更新槽15，不接受忙时新请求。
// 槽0在首个模态读之前就绪，其他槽在轮到它们之前就绪。
// 忙时各槽输出会依次变化；仅当前已更新槽可读，组结束时所有槽一致。
module instrument_env_bank16 #(
    parameter [31:0] P_RELEASE = 4096, G_RELEASE = 2048
)(
    input wire clk, rst_n, start,
    input wire [15:0] gate, note_on, instrument,
    output wire [271:0] env_level_flat,
    output wire [15:0] active,
    output wire busy
);
    function integer count_bits;
        input [31:0] value;
        begin
            count_bits = 0;
            while (value != 0) begin
                count_bits = count_bits + 1;
                value = value >> 1;
            end
            if (count_bits == 0) count_bits = 1;
        end
    endfunction
    localparam [31:0] MAX_RELEASE = (P_RELEASE > G_RELEASE) ? P_RELEASE : G_RELEASE;
    localparam integer CW = count_bits((MAX_RELEASE > 64) ? MAX_RELEASE : 32'd64);
    // 每槽独立状态：levels为Q1.16幅度；bases为整数步长；lefts为段剩余采样数。
    // remainders/errors保存余数累加状态，保证与单声部包络逐样本一致。
    reg [2:0] states[0:15];
    reg [16:0] levels[0:15], bases[0:15];
    reg [CW - 1:0] lefts[0:15], remainders[0:15], errors[0:15];
    // R0锁存整组控制；scanning是读槽流水，step_valid是前一槽的写回有效。
    reg [15:0] gate_frame, start_frame, preset_frame;
    reg scanning, step_valid;
    reg [3:0] scan_slot, step_slot;
    wire accept = start && !busy;
    // 空闲时scan_slot固定为0，采样请求不再进入16选1地址路径。
    wire [3:0] slot = scan_slot;
    wire read_slot = accept || scanning;
    // 输入读取与算术分开一拍，避免16选1译码直接串联完整加减/余数链。
    reg op_gate, op_start, op_instrument;
    reg [2:0] op_state;
    reg [16:0] op_level, op_base;
    reg [CW - 1:0] op_left, op_remainder, op_error;
    wire [2:0] next_state;
    wire [16:0] next_level, next_base;
    wire [CW - 1:0] next_left, next_remainder, next_error;
    // 通用step模块的G/S在此分别对应吉他/钢琴；D=1且S=65536是现有固定预设。
    instrument_env_step #(
        .G_ATTACK(16),
        .G_DECAY(1),
        .G_SUSTAIN(65536),
        .G_RELEASE(G_RELEASE),
        .S_ATTACK(64),
        .S_DECAY(1),
        .S_SUSTAIN(65536),
        .S_RELEASE(P_RELEASE),
        .COUNT_W(CW)
    ) u_step(
        .gate(op_gate),
        .note_on(op_start),
        .instrument(op_instrument),
        .state(op_state),
        .env_level(op_level),
        .base_step(op_base),
        .ticks_left(op_left),
        .remainder(op_remainder),
        .error_acc(op_error),
        .next_state(next_state),
        .next_level(next_level),
        .next_base(next_base),
        .next_left(next_left),
        .next_remainder(next_remainder),
        .next_error(next_error)
    );
    assign busy = scanning || step_valid;
    genvar v;
    generate
        for (v = 0; v < 16; v = v + 1) begin : g_output
            assign env_level_flat[v * 17 +: 17] = levels[v];
            assign active[v] = (states[v] != 0);
        end
    endgenerate
    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            scanning <= 0;
            step_valid <= 0;
            scan_slot <= 0;
            step_slot <= 0;
            gate_frame <= 0;
            start_frame <= 0;
            preset_frame <= 0;
            op_gate <= 0;
            op_start <= 0;
            op_instrument <= 0;
            op_state <= 0;
            op_level <= 0;
            op_base <= 0;
            op_left <= 0;
            op_remainder <= 0;
            op_error <= 0;
            for (k = 0; k < 16; k = k + 1) begin
                states[k] <= 0;
                levels[k] <= 0;
                bases[k] <= 0;
                lefts[k] <= 0;
                remainders[k] <= 0;
                errors[k] <= 0;
            end
        end else begin
            step_valid <= read_slot;
            if (accept) begin
                gate_frame <= gate;
                start_frame <= note_on;
                preset_frame <= instrument;
                scanning <= 1;
                scan_slot <= 1;
            end else if (scanning) begin
                if (scan_slot == 15) begin
                    scanning <= 0;
                    scan_slot <= 0;
                end
                else scan_slot <= scan_slot + 1'b1;
            end
            // 操作数先寄存一拍；同时写回前一槽，不改变R1..R16的公开更新时刻。
            if (read_slot) begin
                step_slot <= slot;
                op_gate <= scanning ? gate_frame[slot] : gate[0];
                op_start <= scanning ? start_frame[slot] : note_on[0];
                op_instrument <= scanning ? preset_frame[slot] : instrument[0];
                op_state <= states[slot];
                op_level <= levels[slot];
                op_base <= bases[slot];
                op_left <= lefts[slot];
                op_remainder <= remainders[slot];
                op_error <= errors[slot];
            end
            if (step_valid) begin
                states[step_slot] <= next_state;
                levels[step_slot] <= next_level;
                bases[step_slot] <= next_base;
                lefts[step_slot] <= next_left;
                remainders[step_slot] <= next_remainder;
                errors[step_slot] <= next_error;
            end
        end
    end
endmodule
