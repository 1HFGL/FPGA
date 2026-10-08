`timescale 1ns/1ps

// 一个机械按键的输入清理：先用两级寄存器同步，再要求新电平持续稳定才接受。
// 两级同步降低异步输入亚稳态传播风险；它不能代替消抖，也不保证物理上零风险。
// 输出level统一为1=按下，与ACTIVE_LOW无关；press/release只各持续一个clk周期。
// 默认250000周期在板级50MHz时为约5ms，还需加同步和边沿检测的少数时钟周期。
module input_sync_debounce #(
    parameter integer ACTIVE_LOW      = 1,
    parameter integer DEBOUNCE_CYCLES = 250000,
    parameter integer CNT_WIDTH       = 32
) (
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire level,
    output reg  press_pulse,
    output reg  release_pulse
);

    reg sync_meta;
    reg sync_q;
    reg stable;
    reg stable_d;
    reg [CNT_WIDTH-1:0] debounce_cnt;

    wire raw_level = (ACTIVE_LOW != 0) ? ~sync_q : sync_q;

    assign level = stable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_meta <= (ACTIVE_LOW != 0) ? 1'b1 : 1'b0;
            sync_q    <= (ACTIVE_LOW != 0) ? 1'b1 : 1'b0;
        end else begin
            sync_meta <= async_in;
            sync_q    <= sync_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable       <= 1'b0;
            stable_d     <= 1'b0;
            debounce_cnt <= {CNT_WIDTH{1'b0}};
        end else begin
            stable_d <= stable;

            if (raw_level != stable) begin
                // 新电平必须连续保持；只要又回到旧电平，下方else就清计数重来。
                if ((DEBOUNCE_CYCLES <= 1) || (debounce_cnt >= (DEBOUNCE_CYCLES - 1))) begin
                    stable       <= raw_level;
                    debounce_cnt <= {CNT_WIDTH{1'b0}};
                end else begin
                    debounce_cnt <= debounce_cnt + 1'b1;
                end
            end else begin
                debounce_cnt <= {CNT_WIDTH{1'b0}};
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            press_pulse   <= 1'b0;
            release_pulse <= 1'b0;
        end else begin
            // 这里读的是本沿之前的stable/stable_d，因此边沿脉冲在stable更新后的
            // 下一个clk沿才输出；不能把“电平变化”和“有效事件”视为同一拍。
            press_pulse   <= stable & ~stable_d;
            release_pulse <= ~stable & stable_d;
        end
    end

endmodule
