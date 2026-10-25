`timescale 1ns/1ps
// 原版来自固定Git提交；新旧RTL、独立十进制模型三方对照，覆盖完整16位输入。
module tb_frame_bend_equivalence;
    reg clk=0,run_clk=1,rst_n=0,commit=0;
    reg signed [15:0] latest=0,framed=0;
    integer raw,checks=0,holds=0;
    reg [11:0] expected;
    always #5 if(run_clk)clk=~clk;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)framed<=0;
        else if(commit)framed<=latest;
    instrument_panel_ui #(.FRAME_BEND(1)) dut(
        .x(12'd0),.y(12'd0),.pitch_bend(framed),.pitch_bend_latest(latest),
        .pixel_clk(clk),.pixel_rst_n(rst_n),.frame_commit(commit));
    instrument_panel_ui comb(.x(12'd0),.y(12'd0),.pitch_bend(latest));
    instrument_panel_ui_reference reference(.x(12'd0),.y(12'd0),.pitch_bend(latest));
    function [11:0] digits_model;
        input [15:0] bits;
        integer magnitude,cents;
        reg [3:0] hundreds,tens,ones;
        begin
            magnitude=bits[15] ? (65536-bits) : bits;
            cents=(magnitude*200+16384)/32768;
            hundreds=cents/100;tens=(cents/10)%10;ones=cents%10;
            digits_model={hundreds,tens,ones};
        end
    endfunction
    initial begin
        #1;rst_n=1;#1;rst_n=0;#1;
        if(dut.bend_digits!==0)begin $display("FAIL frame bend reset");$stop;end
        @(negedge clk);rst_n=1;
        for(raw=0;raw<65536;raw=raw+1)begin
            @(negedge clk);latest=raw;commit=1;
            @(posedge clk);#1;
            expected=digits_model(raw);
            if(dut.bend_digits!==expected || reference.bend_digits!==expected ||
               comb.bend_digits!==expected || framed[15]!==latest[15])begin
                $display("FAIL frame bend value raw=%h new=%h old=%h model=%h",
                         latest,dut.bend_digits,reference.bend_digits,expected);$stop;
            end
            checks=checks+1;
            @(negedge clk);commit=0;latest=raw^16'he35a;
            repeat(3)begin
                @(posedge clk);#1;
                if(dut.bend_digits!==expected)begin $display("FAIL frame bend hold raw=%h",raw);$stop;end
                if(comb.bend_digits!==reference.bend_digits || comb.bend_digits!==digits_model(latest))begin
                    $display("FAIL frame bend combinational compatibility");$stop;
                end
                holds=holds+1;
            end
        end
        @(negedge clk);latest=16'h8000;commit=1;
        @(posedge clk);#1;
        if(dut.bend_digits!==12'h200)begin $display("FAIL frame bend negative extreme");$stop;end
        @(negedge clk);run_clk=0;#2;rst_n=0;#1;
        if(dut.bend_digits!==0 || framed!==0)begin $display("FAIL frame bend stopped-clock reset");$stop;end
        #20;run_clk=1;@(negedge clk);rst_n=1;commit=1;latest=-16'sd16384;
        @(posedge clk);#1;
        if(dut.bend_digits!==12'h100 || !framed[15])begin $display("FAIL frame bend restart");$stop;end
        $display("PASS tb_frame_bend_equivalence: inputs=%0d hold_checks=%0d; old RTL/independent model, default compatibility, negative extreme, stopped-clock reset",checks,holds);
        $finish;
    end
    initial begin #5000000;$display("FAIL frame bend timeout");$stop;end
endmodule
