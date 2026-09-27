`timescale 1ns / 1ns

module pwm (
    input        clk,
    input        rst_n,
    input  [7:0] duty,
    output       pwm
);

    reg [7:0] counter;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) counter <= 8'b0;
        else counter <= counter + 8'b1;

    assign pwm = (counter < duty) ? 1'b1 : 1'b0;




endmodule
