`timescale 1ns/1ps
module tb_final_wave_envelope;
    reg clk=0,rst=0,valid=0,commit=0;
    reg signed [15:0] sample=0;
    reg [7:0] address=0;
    wire signed [15:0] lo,hi;
    wire [15:0] peak;
    wire [3:0] gain;
    wire ready;
    always #10 clk=~clk;
    display_wave_envelope dut(.pixel_clk(clk),.rst_n(rst),.sample_valid(valid),
        .frame_commit(commit),.sample_data(sample),.read_addr(address),
        .read_min(lo),.read_max(hi),.peak_level(peak),.gain_shift(gain),.wave_ready(ready));
    integer i,j,expected_lo,expected_hi,checks=0;
    task send;
        input integer value;
        begin @(negedge clk);sample=value;valid=1;@(negedge clk);valid=0;end
    endtask
    task publish;
        begin @(negedge clk);commit=1;@(negedge clk);commit=0;repeat(3)@(negedge clk);end
    endtask
    task page;
        input integer amplitude;
        begin for(i=0;i<256;i=i+1)begin send(-amplitude);send(amplitude);end publish;end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=1;
        repeat(3)@(negedge clk);
        if(ready || lo!==0 || hi!==0)begin $display("FAIL wave uninitialized RAM exposed");$finish;end
        for(i=0;i<256;i=i+1)begin send(i-1024);send(1024-i);end
        if(ready)begin $display("FAIL wave published before frame commit");$finish;end
        // 等待发布期间的新样本必须丢弃，不能污染已完成的页。
        send(32767);send(-32768);publish;
        if(!ready || peak!==1024 || gain!==4)begin $display("FAIL first AGC/peak %0d x2^%0d",peak,gain);$finish;end
        for(i=0;i<256;i=i+1)begin
            @(negedge clk);address=i;repeat(2)@(negedge clk);
            expected_lo=i-1024;expected_hi=1024-i;checks=checks+1;
            if(lo!==expected_lo[15:0] || hi!==expected_hi[15:0])begin $display("FAIL pair peak lost col=%0d",i);$finish;end
        end
        // 正负满幅不能溢出为零，响音在该页发布时立即降倍率。
        for(i=0;i<256;i=i+1)begin send(-32768);send(32767);end publish;
        if(peak!==32768 || gain!==0)begin $display("FAIL full-scale signed magnitude");$finish;end
        if(lo!==-32768 || hi!==32767)begin $display("FAIL wave signed endpoints");$finish;end
        for(j=0;j<7;j=j+1)begin page(64);if(gain!==0)begin $display("FAIL AGC weak-signal pumping");$finish;end end
        page(64);if(gain!==1)begin $display("FAIL AGC slow release");$finish;end
        page(0);if(peak!==0 || lo!==0 || hi!==0 || gain!==1)begin $display("FAIL silence/AGC retention");$finish;end
        send(30000);rst=0;@(negedge clk);rst=1;repeat(3)@(negedge clk);
        if(ready || peak!==0 || gain!==0 || lo!==0 || hi!==0)begin $display("FAIL wave reset recovery");$finish;end
        page(32);if(peak!==32 || gain!==8)begin $display("FAIL weak-wave gain limit");$finish;end
        $display("PASS tb_final_wave_envelope: %0d bins, full-scale, spikes, atomic pages, x1..256 AGC, quiet/silence/reset",checks);$finish;
    end
    initial begin #1000000;$display("FAIL wave envelope timeout");$finish;end
endmodule
