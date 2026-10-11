`timescale 1ns/1ps
// 真实 50MHz/48kHz 参数；只缩短按键消抖及自动测试保持时间。
module tb_instrument_demo;
    reg clk=0, rst_n=0;
    reg [1:0] keys=2'b11;
    wire bck,ws,din,pa;
    wire auto_bck,auto_ws,auto_din,auto_pa;
    instrument_demo_top #(.DEBOUNCE_CYCLES(8)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(keys),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    instrument_demo_top #(.AUTO_TEST(1),.DEBOUNCE_CYCLES(8),.TEST_HOLD_CYCLES(100000)) auto_dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),
        .HP_BCK(auto_bck),.HP_WS(auto_ws),.HP_DIN(auto_din),.PA_EN(auto_pa));
    always #10 clk=~clk;
    reg [15:0] expected[0:2047], previous_mix=0, received=0;
    integer frames=0, words=0, bits=0, total_words=0, peak_auto=0;
    integer clock_count=0, last_request=0, interval;
    always @(posedge clk) begin
        clock_count=clock_count+1;
        if(!dut.audio_ready) begin
            frames=0; previous_mix=0; last_request=0;
        end else begin
            if(auto_dut.voice_count>peak_auto) peak_auto=auto_dut.voice_count;
            if(dut.sample_request) begin
                if(frames>=2048) begin $display("FAIL: frame scoreboard full"); $finish; end
                expected[frames]=previous_mix;
                if(last_request) begin
                    interval=clock_count-last_request;
                    if(interval!=1041 && interval!=1042) begin $display("FAIL: wrong 48k frame interval"); $finish; end
                end
                last_request=clock_count;
                frames=frames+1;
            end
            if(dut.sample_valid) previous_mix=dut.sample_data;
        end
    end
    always @(posedge bck or negedge rst_n) begin
        if(!rst_n) begin words=0; bits=0; received=0; end
        else if(dut.audio_ready) begin
            if(ws !== (words%2)) begin $display("FAIL: wrong LSBJ channel"); $finish; end
            if(dut.sample_underrun !== (words<2)) begin $display("FAIL: non-startup underrun"); $finish; end
            received={received[14:0],din};
            bits=bits+1;
            if(bits==16) begin
                if(received !== expected[words/2]) begin $display("FAIL: serial mismatch word=%0d",words); $finish; end
                words=words+1; total_words=total_words+1; bits=0;
            end
        end
    end
    task wait_frames(input integer count);
        integer start;
        begin start=frames; wait(frames>=start+count); @(negedge clk); end
    endtask
    initial begin
        repeat(4) @(negedge clk);
        if(pa!==1 || auto_pa!==1) begin $display("FAIL: amp enabled during reset"); $finish; end
        rst_n=1;
        @(posedge clk); #1;
        if(dut.audio_ready!==0) begin $display("FAIL: early reset release"); $finish; end
        @(posedge clk); #1;
        if(dut.audio_ready!==1) begin $display("FAIL: late reset release"); $finish; end
        wait_frames(5);
        if(dut.voice_count!==0 || pa!==1) begin $display("FAIL: idle not muted"); $finish; end
        // 短脉冲不能构成按下；再稳定按住 KEY1。
        keys=2'b10; repeat(3) @(negedge clk); keys=2'b11;
        repeat(20) @(negedge clk);
        if(dut.voice_count!==0) begin $display("FAIL: bounce produced a note"); $finish; end
        keys=2'b10; wait_frames(70);
        if(dut.voice_count!==1 || dut.voice_note_flat[6:0]!==60 || pa!==0)
            begin $display("FAIL: C4 key/audio not connected"); $finish; end
        keys=0; wait_frames(70);
        if(dut.voice_count!==2 || dut.voice_note_flat[13:7]!==64) begin $display("FAIL: two-key chord failed"); $finish; end
        keys=2'b01; wait_frames(70);
        if(dut.voice_count!==1) begin $display("FAIL: first release did not retire voice"); $finish; end
        keys=2'b11; wait_frames(90);
        if(dut.voice_count!==0 || dut.sample_data!==0 || pa!==1) begin $display("FAIL: release did not mute"); $finish; end
        if(peak_auto!=4 || auto_dut.voice_count!==0 || auto_pa!==1)
            begin $display("FAIL: automatic four-voice on/off failed"); $finish; end
        keys=0; wait_frames(45);
        rst_n=0; #1;
        if(pa!==1 || bck!==1 || din!==0) begin $display("FAIL: unsafe mid-stream reset"); $finish; end
        repeat(4) @(negedge clk); rst_n=1;
        wait_frames(70);
        if(dut.voice_count!==2) begin $display("FAIL: held keys did not retrigger after reset"); $finish; end
        keys=2'b11; wait_frames(90);
        if(dut.voice_count!==0 || pa!==1 || total_words<1000) begin $display("FAIL: incomplete restart"); $finish; end
        $display("PASS tb_instrument_demo: keys, four voices, 50MHz/48k, serial, reset, release");
        $finish;
    end
    initial begin #20000000; begin $display("FAIL: instrument timeout"); $finish; end end
endmodule
