`timescale 1ns / 1ns

module dds_sine_tb;

    reg clk;
    reg rst_n;
    reg en;
    reg [3:0] phase_step;
    wire [7:0] wave_out;

    dds_sine dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .phase_step(phase_step),
        .wave_out(wave_out)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    initial begin
        rst_n = 0;
        en = 0;
        phase_step = 0;

        // 在下降沿后改变输入，避开上升沿采样
        repeat (2) @(negedge clk);
        #1;
        rst_n = 1;
        en = 1;
        phase_step = 4'd1;

        repeat (64) @(negedge clk);
        #1;
        phase_step = 4'd2;

        repeat (64) @(negedge clk);
        #1;
        en = 0;

        repeat (8) @(negedge clk);
        $stop;
    end

endmodule
