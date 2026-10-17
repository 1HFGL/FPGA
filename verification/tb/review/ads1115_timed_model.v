`timescale 1ns/1ps
// 验证专用：不是 ADC 的模拟电路模型。每次转换开始锁存输入，直到指定
// 转换时间结束才发布结果；输入恰好错过锁存时，本次仍返回旧值（保守相位）。
// 覆盖本工程使用的单次转换、AIN0/1、±4.096V、128/860 SPS 和 I2C 读写。
module ads1115_timed_model (
    input wire scl,
    inout wire sda
);
    reg connected=1'b1;
    reg [15:0] input0=16'd0, input1=16'd13200;
    reg drive_low=1'b0;
    assign sda=(connected && drive_low)?1'b0:1'bz;
    reg active=1'b0, sending=1'b0, accepted=1'b0;
    reg [1:0] phase=2'd0;
    integer bit_count=0, send_count=0;
    reg [7:0] shift=8'd0, pointer=8'd0;
    reg [15:0] config_word=16'd0, out_shift=16'd0;
    reg [15:0] captured=16'd0, result=16'd0;
    reg conversion_busy=1'b0;
    integer starts0=0, starts1=0, reads=0;
    integer conversion_ns=1350000;
    event conversion_start;

    // 860 SPS: 1/(860*0.9)=1.292ms；另留58us启动/模型余量。
    // 128 SPS用于修复前的回归复现。该模型不证明实物模拟建立时间。
    always @(conversion_start) begin
        conversion_busy=1'b1;
        #(conversion_ns);
        result=captured;
        conversion_busy=1'b0;
    end

    always @(negedge sda) if(scl) begin
        active<=1'b1; sending<=1'b0; phase<=2'd0;
        bit_count<=0; shift<=8'd0; drive_low<=1'b0; send_count<=0;
    end
    always @(posedge sda) if(scl) begin
        active<=1'b0; sending<=1'b0; drive_low<=1'b0;
    end
    always @(posedge scl) if(active && !sending) begin
        if(bit_count<8) shift<={shift[6:0],sda};
        bit_count<=bit_count+1;
    end
    always @(negedge scl) begin
        if(!active) drive_low<=1'b0;
        else if(sending) begin
            if(send_count<8 || (send_count>=9 && send_count<17)) begin
                drive_low<=!out_shift[15];
                out_shift<={out_shift[14:0],1'b0}; send_count<=send_count+1;
            end else if(send_count==8) begin
                drive_low<=1'b0; send_count<=9;
            end else drive_low<=1'b0;
        end else if(bit_count==8) begin
            accepted=connected && ((phase!=0) || (shift[7:1]==7'h48));
            drive_low<=accepted;
        end else if(bit_count==9) begin
            drive_low<=1'b0; bit_count<=0;
            if(!accepted) active<=1'b0;
            else case(phase)
                0: if(shift[0]) begin
                    if(pointer!=0 || conversion_busy) begin
                        $display("FAIL timed ADC: read before conversion ready, pointer=%h",pointer);
                        $stop;
                    end
                    reads=reads+1;
                    out_shift<={result[14:0],1'b0}; drive_low<=!result[15];
                    sending<=1'b1; send_count<=1;
                end else phase<=1;
                1: begin pointer<=shift; phase<=2; end
                2: begin config_word[15:8]<=shift; phase<=3; end
                3: begin
                    config_word[7:0]=shift; phase<=0;
                    if(pointer!=1 || config_word[11:9]!=1 || !config_word[8] ||
                       !config_word[15] || (config_word[14:12]!=4 && config_word[14:12]!=5)) begin
                        $display("FAIL timed ADC: unsupported config %h",config_word); $stop;
                    end
                    if(conversion_busy) begin
                        $display("FAIL timed ADC: conversion restarted too early"); $stop;
                    end
                    case(config_word[7:5])
                        3'b100: conversion_ns=9000000;
                        3'b111: conversion_ns=1350000;
                        default: begin $display("FAIL timed ADC: unexpected data rate"); $stop; end
                    endcase
                    captured=(config_word[14:12]==4)?input0:input1;
                    if(config_word[14:12]==4) starts0=starts0+1;
                    else starts1=starts1+1;
                    -> conversion_start;
                end
            endcase
        end else drive_low<=1'b0;
    end
endmodule
