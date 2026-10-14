`timescale 1ns/1ps

// 将多个按键的单拍边沿变成有顺序的事件：1=按下(note-on)，0=松开(note-off)。
// FIFO（先进先出队列）供声部分配器逐条读取；仅event_valid && event_ready时出队。
// 接收端未ready时保持队头不动；event_valid=0时字段值没有意义，不能当作新事件。
// pending_on/off每键各只有一位，不是无限事件队列：长期堵塞可能合并重复边沿，
// 不保证极端背压下全保序/不丢事件；当前两键人手操作验证不等于消除了这个限制。
// 当前默认MAX_EVENTS=64、PTR_WIDTH=6，指针靠自然回绕，不能随意改为非2的幂深度。
module event_encoder #(
    parameter integer KEY_COUNT    = 2,
    parameter integer MAX_EVENTS   = 64,
    parameter integer PTR_WIDTH    = 6,
    parameter integer SOURCE_WIDTH = 5,
    parameter integer CHROMATIC_KEYS = 0,
    parameter integer NOTE_BASE = 60
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [KEY_COUNT-1:0] key_press,
    input  wire [KEY_COUNT-1:0] key_release,
    input  wire [KEY_COUNT*7-1:0] key_velocity_flat,
    input  wire [3:0] input_timbre,
    output wire event_valid,
    output wire event_type,
    output wire [SOURCE_WIDTH-1:0] event_source_id,
    output wire [6:0] event_note,
    output wire [6:0] event_velocity,
    output wire [3:0] event_timbre,
    input  wire event_ready
);

    localparam integer EVENT_WIDTH = SOURCE_WIDTH + 19;

    // 队列条目打包顺序：类型1位 + 来源编号 + 音符7位 + 增益7位 + 音色4位。
    // pending先收下同拍的多键变化，再每个clk至多搬一条进FIFO。
    reg pending_on  [0:KEY_COUNT-1];
    reg pending_off [0:KEY_COUNT-1];
    reg [EVENT_WIDTH-1:0] fifo_mem [0:MAX_EVENTS-1];
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [PTR_WIDTH:0]   fifo_count;

    integer i;
    integer sel_idx;
    integer on_idx;
    integer off_idx;
    reg sel_is_on;
    reg has_on;
    reg has_off;
    reg [SOURCE_WIDTH-1:0] sel_source_id;
    reg [6:0] sel_velocity;
    reg [EVENT_WIDTH-1:0] wr_data;
    wire [EVENT_WIDTH-1:0] rd_data;
    wire do_read;
    wire do_write;

    function [6:0] key_to_note;
        input integer key_index;
        integer mapped_note;
        begin
            if (CHROMATIC_KEYS) begin
                mapped_note = NOTE_BASE + key_index;
                key_to_note = mapped_note[6:0];
            end else begin
            // 当前2键选C4/E4；前4键是C/E/G/C，不是13键连续半音布局。
            // 因此以后只把KEY_COUNT改成13还不够，必须同时修改映射与板级引脚。
            case (key_index)
                0: key_to_note = 7'd60;
                1: key_to_note = 7'd64;
                2: key_to_note = 7'd67;
                3: key_to_note = 7'd72;
                default: key_to_note = 7'd60 + key_index[6:0];
            endcase
            end
        end
    endfunction

    assign event_valid    = (fifo_count != 0);
    assign rd_data        = fifo_mem[rd_ptr];
    assign event_type     = rd_data[SOURCE_WIDTH+18];
    assign event_source_id = rd_data[SOURCE_WIDTH+17:18];
    assign event_note     = rd_data[17:11];
    assign event_velocity = rd_data[10:4];
    assign event_timbre   = rd_data[3:0];

    assign do_read  = event_valid & event_ready;
    assign do_write = (has_on | has_off) & (fifo_count < MAX_EVENTS);

    always @* begin
        // 按下事件优先于松开，同类事件编号小的键优先。
        // 下方循环从大到小赋值，后遇到的小编号会覆盖早先候选，不是反过来。
        has_on      = 1'b0;
        has_off     = 1'b0;
        on_idx      = 0;
        off_idx     = 0;
        sel_idx     = 0;
        sel_is_on   = 1'b1;
        sel_source_id = {SOURCE_WIDTH{1'b0}};
        sel_velocity  = 7'd0;
        wr_data       = {EVENT_WIDTH{1'b0}};

        for (i = KEY_COUNT-1; i >= 0; i = i - 1) begin
            if (pending_on[i]) begin
                has_on = 1'b1;
                on_idx = i;
            end
        end

        for (i = KEY_COUNT-1; i >= 0; i = i - 1) begin
            if (pending_off[i]) begin
                has_off = 1'b1;
                off_idx = i;
            end
        end

        if (has_on) begin
            sel_idx       = on_idx;
            sel_is_on     = 1'b1;
            sel_source_id = on_idx;
            sel_velocity  = key_velocity_flat[on_idx*7 +: 7];
            wr_data       = {1'b1, sel_source_id, key_to_note(on_idx), sel_velocity, input_timbre};
        end else if (has_off) begin
            sel_idx       = off_idx;
            sel_is_on     = 1'b0;
            sel_source_id = off_idx;
            sel_velocity  = 7'd0;
            wr_data       = {1'b0, sel_source_id, key_to_note(off_idx), 7'd0, input_timbre};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= {PTR_WIDTH{1'b0}};
            rd_ptr     <= {PTR_WIDTH{1'b0}};
            fifo_count <= {(PTR_WIDTH+1){1'b0}};
            for (i = 0; i < KEY_COUNT; i = i + 1) begin
                pending_on[i]  <= 1'b0;
                pending_off[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < KEY_COUNT; i = i + 1) begin
                if (key_press[i]) begin
                    pending_on[i] <= 1'b1;
                end
                if (key_release[i]) begin
                    pending_off[i] <= 1'b1;
                end
            end

            if (do_write) begin
                // 入队时清pending；同键同类型新边沿恰好同拍到达也会被该清除覆盖。
                // 当前只说明既有边界行为，注释改动不声称修复长期背压问题。
                fifo_mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
                if (sel_is_on) begin
                    pending_on[sel_idx] <= 1'b0;
                end else begin
                    pending_off[sel_idx] <= 1'b0;
                end
            end

            if (do_read) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            if (do_read & do_write) begin
                fifo_count <= fifo_count;
            end else if (do_write) begin
                fifo_count <= fifo_count + 1'b1;
            end else if (do_read) begin
                fifo_count <= fifo_count - 1'b1;
            end
        end
    end

endmodule
