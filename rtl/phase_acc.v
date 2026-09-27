`timescale 1ns/1ps

module phase_acc (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    input  wire [31:0] phase_inc,
    output reg  [31:0] phase,
    output wire [9:0]  wave_addr
);

    // 高电平同步复位；sample_tick 是使能，不是时钟。
    always @(posedge clk) begin
        if (rst)
            phase <= 32'd0;
        else if (sample_tick)
            phase <= phase + phase_inc;
        // 未使能时保持；32 位加法溢出后自然回绕。
    end

    // 取高 10 位作为后续 1024 点波表的地址。
    assign wave_addr = phase[31:22];

endmodule
