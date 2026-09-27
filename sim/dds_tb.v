`timescale 1ns / 1ns
`define clock_period 20

module dds_tb;

    reg clk;
    reg rst_n;
    reg en;
    reg [7:0] phase_step;
    wire wave_out;

    dds dds0 (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .phase_step(phase_step),
        .wave_out(wave_out)
    );

    initial clk = 1;
    always #(`clock_period / 2) clk = ~clk;

    initial begin
        rst_n = 0;
        en = 0;
        phase_step = 8'd0;
        #(`clock_period * 2);
        rst_n = 1;
        en = 1;
        phase_step = 8'd1;
        #(`clock_period * 200);
        rst_n = 0;
        en = 0;
        #(`clock_period * 2);
        rst_n = 1;
        en = 1;
        phase_step = 8'd2;
        #(`clock_period * 200);
        rst_n = 0;
        en = 0;
        #(`clock_period * 2);
        rst_n = 1;
        en = 1;
        phase_step = 8'd4;
        #(`clock_period * 200);
        $finish;
    end

endmodule
