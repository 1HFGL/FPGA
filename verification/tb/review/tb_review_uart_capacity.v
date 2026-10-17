`timescale 1ns/1ps
// 独立协议参考：常量期望由Verilog格式化生成，逐字节检查容量及停顿稳定性。
module uart_capacity_case #(parameter integer CAPACITY=4,parameter integer PIANO=0)(output reg done=0);
    reg clk=0,rst_n=0,hello=0;
    wire [7:0] data;
    wire valid;
    integer cycle=0,index=0,length=0,lines=0,k;
    reg [8191:0] expected_line;
    reg stalled=0;
    reg [7:0] held_data;
    wire ready=(cycle%5==0) && !(cycle>=20 && cycle<45);
    always #10 clk=~clk;
    uart_reply_tx #(.FIXED_PIANO(PIANO==1),.ENABLE_GUITAR(PIANO==2),.VOICES(CAPACITY)) dut(
        .clk(clk),.rst_n(rst_n),.hello_req(hello),.status_req(1'b0),.error_req(1'b0),
        .voice_count(6'd0),.max_voice_count(6'd0),.steal_count(32'd0),
        .error_sequence(32'd0),.error_code(3'd0),.tx_data(data),.tx_valid(valid),.tx_ready(ready));
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!rst_n)begin index=0;lines=0;stalled=0;end
        else begin
            if(stalled && (!valid || data!==held_data))begin
                $display("FAIL capacity stall capacity=%0d piano=%0d",CAPACITY,PIANO);$finish;
            end
            if(valid && ready)begin
                if(index>=length || data!==expected_line[(length-1-index)*8+:8])begin
                    $display("FAIL capacity byte capacity=%0d piano=%0d index=%0d got=%h",CAPACITY,PIANO,index,data);$finish;
                end
                index=index+1;
                if(data==10)begin
                    if(index!=length)begin $display("FAIL capacity premature newline");$finish;end
                    index=0;lines=lines+1;
                end
            end
            stalled=valid && !ready;held_data=data;
        end
    end
    initial begin
        if(PIANO==2)$sformat(expected_line,"SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=%0d SAMPLE_RATE=48000 FW=uart-dual-v1 TONE=PIANO_GUITAR\n",CAPACITY);
        else if(PIANO==1)$sformat(expected_line,"SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=%0d SAMPLE_RATE=48000 FW=uart-piano-v1 TONE=FIXED_PIANO\n",CAPACITY);
        else $sformat(expected_line,"SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=%0d SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE\n",CAPACITY);
        for(k=0;k<1024;k=k+1)if(expected_line[k*8+:8]!=0)length=k+1;
        repeat(4)@(negedge clk);rst_n=1;hello=1;@(negedge clk);hello=0;
        wait(lines==1);@(negedge clk);hello=1;@(negedge clk);hello=0;
        // 中断第二次握手，再从首字符重新发送，不能残留旧串行化位置。
        wait(index==6);@(negedge clk);rst_n=0;
        repeat(3)@(negedge clk);if(valid!==0)begin $display("FAIL capacity reset valid");$finish;end
        rst_n=1;hello=1;@(negedge clk);hello=0;
        wait(lines==1);repeat(10)@(negedge clk);
        if(lines!=1)begin $display("FAIL capacity duplicate reply");$finish;end
        done=1;
    end
endmodule

module tb_review_uart_capacity;
    wire [17:0] done;
    genvar n;
    generate for(n=0;n<18;n=n+1)begin:g_case
        localparam integer CAP=(n%6==0)?1:(n%6==1)?4:(n%6==2)?9:(n%6==3)?10:(n%6==4)?16:32;
        uart_capacity_case #(.CAPACITY(CAP),.PIANO(n/6)) test(.done(done[n]));
    end endgenerate
    initial begin
        wait(&done);
        $display("PASS tb_review_uart_capacity: 18 capacity/tone combinations, exact bytes, stalls and mid-reply reset");$finish;
    end
    initial begin #1000000;$display("FAIL capacity cases timeout");$finish;end
endmodule
