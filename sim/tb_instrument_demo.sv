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
                if(frames>=2048) $fatal(1,"frame scoreboard full");
                expected[frames]=previous_mix;
                if(last_request) begin
                    interval=clock_count-last_request;
                    if(interval!=1041 && interval!=1042) $fatal(1,"wrong 48k frame interval");
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
            if(ws !== (words%2)) $fatal(1,"wrong LSBJ channel");
            if(dut.sample_underrun !== (words<2)) $fatal(1,"non-startup underrun");
            received={received[14:0],din};
            bits=bits+1;
            if(bits==16) begin
                if(received !== expected[words/2]) $fatal(1,"serial mismatch word=%0d",words);
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
        if(pa!==1 || auto_pa!==1) $fatal(1,"amp enabled during reset");
        rst_n=1;
        @(posedge clk); #1;
        if(dut.audio_ready!==0) $fatal(1,"early reset release");
        @(posedge clk); #1;
        if(dut.audio_ready!==1) $fatal(1,"late reset release");
        wait_frames(5);
        if(dut.voice_count!==0 || pa!==1) $fatal(1,"idle not muted");
        // 短脉冲不能构成按下；再稳定按住 KEY1。
        keys=2'b10; repeat(3) @(negedge clk); keys=2'b11;
        repeat(20) @(negedge clk);
        if(dut.voice_count!==0) $fatal(1,"bounce produced a note");
        keys=2'b10; wait_frames(70);
        if(dut.voice_count!==1 || dut.voice_note_flat[6:0]!==60 || pa!==0)
            $fatal(1,"C4 key/audio not connected");
        keys=0; wait_frames(70);
        if(dut.voice_count!==2 || dut.voice_note_flat[13:7]!==64) $fatal(1,"two-key chord failed");
        keys=2'b01; wait_frames(70);
        if(dut.voice_count!==1) $fatal(1,"first release did not retire voice");
        keys=2'b11; wait_frames(90);
        if(dut.voice_count!==0 || dut.sample_data!==0 || pa!==1) $fatal(1,"release did not mute");
        if(peak_auto!=4 || auto_dut.voice_count!==0 || auto_pa!==1)
            $fatal(1,"automatic four-voice on/off failed");
        keys=0; wait_frames(45);
        rst_n=0; #1;
        if(pa!==1 || bck!==1 || din!==0) $fatal(1,"unsafe mid-stream reset");
        repeat(4) @(negedge clk); rst_n=1;
        wait_frames(70);
        if(dut.voice_count!==2) $fatal(1,"held keys did not retrigger after reset");
        keys=2'b11; wait_frames(90);
        if(dut.voice_count!==0 || pa!==1 || total_words<1000) $fatal(1,"incomplete restart");
        $display("PASS tb_instrument_demo: keys, four voices, 50MHz/48k, serial, reset, release");
        $finish;
    end
    initial begin #20000000; $fatal(1,"instrument timeout"); end
endmodule
