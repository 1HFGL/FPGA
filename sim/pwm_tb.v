`timescale 1ns / 1ns
`define clock_period 20

module pwm_tb;

    reg clk;
    reg rst_n;
    reg [7:0] duty;

    wire pwm_out;
    pwm pwm0 (
        .clk(clk),
        .rst_n(rst_n),
        .duty(duty),
        .pwm(pwm_out)
    );

    initial clk = 1;
    always #(`clock_period / 2) clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        duty = 8'd128;  // 设置占空比为 50%

        // 复位两个时钟周期
        #(`clock_period * 2);

        // 释放复位，开始 PWM 输出
        rst_n = 1'b1;

        // 运行一段时间以观察 PWM 输出
        #(`clock_period * 100);

        $finish;
    end

endmodule
