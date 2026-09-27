`timescale 1ns / 1ns
`define clock_period 20

module counter_tb;

    reg clk;
    reg rst_n;
    reg en;

    wire [3:0] q;

    counter counter0 (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .q(q)
    );


    initial clk = 1;
    always #(`clock_period / 2) clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        en = 1'b0;

        // 复位两个时钟周期
        #(`clock_period * 2);

        // 释放复位，开始计数
        rst_n = 1'b1;
        en = 1'b1;

        // 计数 20 个时钟周期
        #(`clock_period * 20);

        // 关闭使能，观察 q 是否保持
        en = 1'b0;
        #(`clock_period * 4);

        $finish;
    end

endmodule
