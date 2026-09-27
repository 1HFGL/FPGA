`timescale  1ns/1ns
`define clock_period 20

module bcd_counter_tb;

    reg clk;
    reg cin;
    reg rst_n;

    wire cout;
    wire [3:0] q;

bcd_counter bcd_counter0(
    .clk(clk),
    .cin(cin),  
    .rst_n(rst_n),
    .cout(cout),
    .q(q)
);

    initial clk = 1;
    always #(`clock_period / 2) clk = ~clk;

    initial begin
        rst_n = 0;
        cin = 0;
        #(`clock_period * 200);
        rst_n = 1;
        #(`clock_period * 200);
        cin = 1;
        #(`clock_period * 200);
        cin = 0;
        #(`clock_period * 200);
        cin = 1;
        #(`clock_period * 200);
        cin = 0;
        #(`clock_period * 200);
        cin = 1;
        #(`clock_period * 200);
        cin = 0;
        #(`clock_period * 200);
        cin = 1;
        #(`clock_period * 200);
        cin = 0;
        #(`clock_period * 200);
        cin = 1;
        #(`clock_period * 200);
        cin = 0;
    end
endmodule