`timescale 1ns/1ps
// 正式主顶层/真实50MHz、48kHz、2ms消抖与钢琴包络；数字串行左声道终点。
// 每次复位后首次起音；13音高覆盖不同输入相位，不等于穷举最坏物理延迟。
module tb_performance_latency;
    reg clk=0,rst_n=0;
    reg [12:0] keys=13'h1fff;
    tri1 sda;
    wire scl,tx,bck,ws,din,pa;
    integer cycle=0,start=0,first=0,bits=0,k,maximum=0,delta;
    reg [15:0] word=0;
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem")) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(keys),.uart_rx(1'b1),
        .uart_tx(tx),.HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_sda(sda),.knob_scl(scl));
    always #10 clk=~clk;
    always @(posedge clk)cycle=cycle+1;
    always @(posedge bck)if(dut.core_ready)begin
        word={word[14:0],din};bits=bits+1;
        if(bits==16)begin
            bits=0;
            if(start!=0 && first==0 && !ws && word!=0)first=cycle;
        end
    end
    initial begin
        for(k=0;k<13;k=k+1)begin
            @(negedge clk);rst_n=0;keys=13'h1fff;start=0;first=0;bits=0;word=0;
            repeat(8)@(negedge clk);rst_n=1;
            repeat(5000+k*241)@(negedge clk);
            start=cycle;keys[k]=0;
            wait(first!=0);@(negedge clk);delta=(first-start)*20;
            if(delta<2000000 || delta>2200000)begin $display("FAIL: digital production onset %0d",delta);$finish;end
            if(delta>maximum)maximum=delta;
            $display("OBS key=%0d digital_contact_to_left_DAC_word_ns=%0d",k,delta);
        end
        $display("PASS tb_performance_latency: 13 production onsets; maximum_observed_ns=%0d; analog/contact bounce excluded",maximum);$finish;
    end
    initial begin #50000000;$display("FAIL: latency timeout");$finish;end
endmodule
