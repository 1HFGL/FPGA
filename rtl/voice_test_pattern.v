`timescale 1ns/1ps

// 自动测试事件源，不是歌曲播放器：按顺序开N个不同音符，保持，再逐个松开。
// 仅test_enable的上升沿启动一次；一直拉高不会循环。复位后可重新启动。
// NOTE_BASE=36、test_voices=4时为C2/C#2/D2/D#2，是相邻半音，听感可能不和谐。
// HOLD_CYCLES使用系统clk计数（50MHz下50000000为约1秒），不是音频采样点。
// 末尾test_done表示“松键事件已发送”，不表示A的120ms尾音已经播放完毕。
module voice_test_pattern #(
    parameter integer SOURCE_WIDTH = 5,
    parameter integer NOTE_BASE    = 36,
    parameter integer HOLD_CYCLES  = 50000000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire test_enable,
    input  wire test_clear,
    input  wire [5:0] test_voices,
    output reg  test_event_valid,
    input  wire test_event_ready,
    output reg  test_event_type,
    output reg  [SOURCE_WIDTH-1:0] test_source_id,
    output reg  [6:0] test_note,
    output reg  [6:0] test_velocity,
    output reg  [3:0] test_timbre,
    output reg  test_busy,
    output reg  test_done
);

    localparam [1:0] T_IDLE = 2'd0;
    localparam [1:0] T_ON   = 2'd1;
    localparam [1:0] T_HOLD = 2'd2;
    localparam [1:0] T_OFF  = 2'd3;

    reg [1:0] state;
    reg [5:0] count_reg;
    reg [5:0] idx;
    reg [31:0] hold_cnt;
    reg test_enable_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= T_IDLE;
            count_reg <= 6'd32;
            idx <= 6'd0;
            hold_cnt <= 32'd0;
            test_enable_d <= 1'b0;
            test_event_valid <= 1'b0;
            test_event_type <= 1'b0;
            test_source_id <= {SOURCE_WIDTH{1'b0}};
            test_note <= 7'd0;
            test_velocity <= 7'd0;
            test_timbre <= 4'd0;
            test_busy <= 1'b0;
            test_done <= 1'b0;
        end else begin
            test_enable_d <= test_enable;

            case (state)
                T_IDLE: begin
                    test_event_valid <= 1'b0;
                    test_busy <= 1'b0;
                    test_done <= 1'b0;
                    if (test_enable && !test_enable_d) begin
                        count_reg <= (test_voices == 6'd0) ? 6'd32 : test_voices;
                        idx <= 6'd0;
                        hold_cnt <= 32'd0;
                        test_busy <= 1'b1;
                        state <= T_ON;
                    end
                end

                T_ON: begin
                    // valid置1后等待ready，不先推进idx；背压期间事件字段保持不变。
                    if (!test_event_valid) begin
                        if (idx < count_reg) begin
                            test_event_valid <= 1'b1;
                            test_event_type <= 1'b1;
                            test_source_id <= idx[SOURCE_WIDTH-1:0];
                            test_note <= NOTE_BASE[6:0] + idx;
                            test_velocity <= 7'd100;
                            test_timbre <= idx[3:0];
                        end else begin
                            hold_cnt <= 32'd0;
                            state <= T_HOLD;
                        end
                    end else if (test_event_ready) begin
                        test_event_valid <= 1'b0;
                        if ((idx + 1'b1) >= count_reg) begin
                            idx <= 6'd0;
                            hold_cnt <= 32'd0;
                            state <= T_HOLD;
                        end else begin
                            idx <= idx + 1'b1;
                        end
                    end
                end

                T_HOLD: begin
                    test_event_valid <= 1'b0;
                    if (test_clear) begin
                        idx <= 6'd0;
                        state <= T_OFF;
                    end else if (hold_cnt >= (HOLD_CYCLES - 1)) begin
                        idx <= 6'd0;
                        state <= T_OFF;
                    end else begin
                        hold_cnt <= hold_cnt + 1'b1;
                    end
                end

                T_OFF: begin
                    if (!test_event_valid) begin
                        if (idx < count_reg) begin
                            test_event_valid <= 1'b1;
                            test_event_type <= 1'b0;
                            test_source_id <= idx[SOURCE_WIDTH-1:0];
                            test_note <= NOTE_BASE[6:0] + idx;
                            test_velocity <= 7'd0;
                            test_timbre <= 4'd0;
                        end else begin
                            test_busy <= 1'b0;
                            test_done <= 1'b1;
                            state <= T_IDLE;
                        end
                    end else if (test_event_ready) begin
                        test_event_valid <= 1'b0;
                        idx <= idx + 1'b1;
                    end
                end

                default: begin
                    state <= T_IDLE;
                    test_event_valid <= 1'b0;
                    test_busy <= 1'b0;
                    test_done <= 1'b0;
                end
            endcase
        end
    end

endmodule
