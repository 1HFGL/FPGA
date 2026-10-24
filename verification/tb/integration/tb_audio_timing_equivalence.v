`timescale 1ns/1ps
// 原实现由脚本从改动前工作区冻结到build，不复制为第二套有效RTL。
// 对比每拍请求、帧起点、全部DAC引脚和欠载；独立整数余数模型防止两份实现同错。
module tb_audio_timing_equivalence;
    reg clk=0;
    wire [11:0] done;
    always #5 clk=~clk;
    audio_timing_case #(.ID(0)) c0(clk,done[0]);
    audio_timing_case #(.ID(1),.RATE(44100),.LEAD(0)) c1(clk,done[1]);
    audio_timing_case #(.ID(2),.FREQ(640),.RATE(10),.LEAD(1)) c2(clk,done[2]);
    audio_timing_case #(.ID(3),.FREQ(1024),.RATE(16),.LEAD(63)) c3(clk,done[3]);
    audio_timing_case #(.ID(4),.FREQ(1024),.RATE(1),.LEAD(32)) c4(clk,done[4]);
    audio_timing_case #(.ID(5),.FREQ(67),.RATE(1),.LEAD(2)) c5(clk,done[5]);
    audio_timing_case #(.ID(6),.FREQ(4),.RATE(1),.SLOT(1),.LEAD(3)) c6(clk,done[6]);
    audio_timing_case #(.ID(7),.FREQ(29),.RATE(1),.SLOT(7),.LEAD(27)) c7(clk,done[7]);
    audio_timing_case #(.ID(8),.FREQ(65536),.RATE(1),.SLOT(16384),.LEAD(65535)) c8(clk,done[8]);
    audio_timing_case #(.ID(9),.FREQ(2147483647),.RATE(33554431),.LEAD(60)) c9(clk,done[9]);
    audio_timing_case #(.ID(10),.FREQ(2147483647),.RATE(12345),.LEAD(1)) c10(clk,done[10]);
    audio_timing_case #(.ID(11),.FREQ(25000000),.RATE(48000),.LEAD(2)) c11(clk,done[11]);
    initial begin
        wait(&done);
        $display("PASS tb_audio_timing_equivalence: 12 parameter cases, 3600000 cycle comparisons, asynchronous reset, full-rate/maximum-width, DAC boundary/collision/underrun");
        $finish;
    end
    initial begin #4000000; $display("FAIL audio timing timeout"); $finish; end
endmodule

module audio_timing_case #(
    parameter integer ID=0,FREQ=50000000,RATE=48000,SLOT=16,LEAD=60
)(input wire clk,output reg done=0);
    reg rst_n=0;
    wire ce,frame,request,old_ce,old_frame,old_request;
    reg signed [15:0] data=0;
    reg valid=0;
    wire [3:0] serial,old_serial;
    reg [31:0] random_state=32'h9d7a6c31;
    reg [63:0] residue=0;
    reg expected_ce;
    integer edge_index=0,cycles=0,frames=0,requests=0,collisions=0,empty_frames=0;
    localparam integer EDGES=4*SLOT;
    localparam integer REQUEST_INDEX=LEAD==0 ? 0 : EDGES-LEAD;
    sample_tick #(.AUDIO_CLK_HZ(FREQ),.SAMPLE_RATE_HZ(RATE),.SLOT_BITS(SLOT),
        .REQUEST_LEAD_HALF_EDGES(LEAD)) dut(clk,rst_n,ce,frame,request);
    sample_tick_before #(.AUDIO_CLK_HZ(FREQ),.SAMPLE_RATE_HZ(RATE),.SLOT_BITS(SLOT),
        .REQUEST_LEAD_HALF_EDGES(LEAD)) reference(clk,rst_n,old_ce,old_frame,old_request);
    generate if(SLOT==16)begin:g_serial
        i2s_tx tx(clk,rst_n,ce,frame,data,valid,serial[3],serial[2],serial[1],serial[0]);
        i2s_tx_before reference_tx(clk,rst_n,old_ce,old_frame,data,valid,
            old_serial[3],old_serial[2],old_serial[1],old_serial[0]);
    end else begin:g_tick_only
        assign serial=0;
        assign old_serial=0;
    end endgenerate

    // 参考模型使用64位加法和模运算，避免照搬被优化的阈值表达式。
    always @(posedge clk)begin
        if(!rst_n)begin residue=0;edge_index=0;end
        else if(!done)begin
            residue=residue+64'd4*SLOT*RATE;
            expected_ce=residue>=FREQ;
            if({ce,frame,request} !== {old_ce,old_frame,old_request} ||
                ce !== expected_ce || frame !== (expected_ce && edge_index==0) ||
                request !== (expected_ce && edge_index==REQUEST_INDEX))begin
                $display("FAIL audio tick mismatch case=%0d cycle=%0d",ID,cycles);$finish;
            end
            if(expected_ce)begin
                residue=residue%FREQ;
                edge_index=(edge_index+1)%EDGES;
            end
            if(frame)begin
                frames=frames+1;
                if(valid)collisions=collisions+1;
            end
            if(request)requests=requests+1;
        end
        #1;
        if(serial !== old_serial)begin
            $display("FAIL audio serial mismatch case=%0d cycle=%0d",ID,cycles);$finish;
        end
        if(frame && serial[0])empty_frames=empty_frames+1;
    end

    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(cycles=0;cycles<300000;cycles=cycles+1)begin
            @(negedge clk);
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            data=random_state[15:0];
            // 含随机多次覆盖、长时间断粮、恰在帧边界写入和重新恢复。
            valid=(cycles%20000<14000) && (random_state[3:0]==0 || frame);
            if(cycles==1007 || cycles==50023)begin
                #2;rst_n=0;#1;
                if({ce,frame,request}!==3'b000 || serial!==old_serial)begin
                    $display("FAIL audio asynchronous reset case=%0d",ID);$finish;
                end
                residue=0;edge_index=0;
                @(negedge clk);rst_n=1;
            end
        end
        if(frames<2 || requests<1 || (SLOT==16 && collisions==0))begin
            $display("FAIL audio coverage case=%0d frames=%0d requests=%0d collisions=%0d",ID,frames,requests,collisions);$finish;
        end
        done=1;
    end
endmodule
