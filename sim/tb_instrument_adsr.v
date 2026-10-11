`timescale 1ns/1ps
// 系统保持真实50MHz/48kHz；仅缩短包络采样点数和消抖以加速联调。
// 默认包络时长另由 tb_voice_bank_adsr + Python 核对，不能用此仿真报实物延迟。
module tb_instrument_adsr;
    reg clk=0, rst_n=0;
    reg [1:0] keys=3;
    wire bck,ws,din,pa,abck,aws,adin,apa;
    instrument_adsr_top #(.DEBOUNCE_CYCLES(8), .ATTACK_SAMPLES(5),
        .DECAY_SAMPLES(7), .RELEASE_SAMPLES(13)) dut (
        .sys_clk(clk), .sys_rst_n(rst_n), .Key_in(keys),
        .HP_BCK(bck), .HP_WS(ws), .HP_DIN(din), .PA_EN(pa));
    instrument_adsr_top #(.AUTO_TEST(1), .DEBOUNCE_CYCLES(8), .TEST_HOLD_CYCLES(100000),
        .ATTACK_SAMPLES(5), .DECAY_SAMPLES(7), .RELEASE_SAMPLES(13)) auto_dut (
        .sys_clk(clk), .sys_rst_n(rst_n), .Key_in(2'b11),
        .HP_BCK(abck), .HP_WS(aws), .HP_DIN(adin), .PA_EN(apa));
    always #10 clk=~clk;
    reg [15:0] expected[0:1023], previous=0, received=0;
    integer frames=0, words=0, bits=0, total=0, peak=0, cycle=0, last_request=0;
    integer accepted=0, requested_at=0, triggers=0;
    integer nonzero_words=0, auto_nonzero_words=0, auto_requested_at=0;
    integer auto_frames=0, auto_words=0, auto_bits=0;
    reg [15:0] auto_expected[0:1023], auto_previous=0, auto_received=0;
    always @(posedge clk) begin
        cycle=cycle+1;
        if(!dut.audio_ready) begin
            frames=0; previous=0; last_request=0; requested_at=0;
        end else begin
            if(auto_dut.voice_count>peak) peak=auto_dut.voice_count;
            if(|dut.voice_trigger) triggers=triggers+1;
            if(dut.sample_request) begin
                if(frames>=1024) begin $display("FAIL: ADSR frame scoreboard full"); $finish; end
                expected[frames]=previous;
                if(last_request && cycle-last_request!=1041 && cycle-last_request!=1042)
                    begin $display("FAIL: ADSR wrong frame interval"); $finish; end
                last_request=cycle; requested_at=cycle; frames=frames+1;
            end
            if(dut.sample_valid) begin
                if(cycle-requested_at!=4) begin $display("FAIL: ADSR B did not receive at R4"); $finish; end
                if(dut.sample_clipped!==0) begin $display("FAIL: quiet manual mix clipped"); $finish; end
                previous=dut.sample_data; accepted=accepted+1;
            end
        end
        // 自动四声部也逐字核对真实串行输出，不只看分配器计数。
        if(!auto_dut.audio_ready) begin
            auto_frames=0; auto_previous=0; auto_requested_at=0;
        end else begin
            if(auto_dut.sample_request) begin
                if(auto_frames>=1024) begin $display("FAIL: automatic frame scoreboard full"); $finish; end
                auto_expected[auto_frames]=auto_previous;
                auto_requested_at=cycle; auto_frames=auto_frames+1;
            end
            if(auto_dut.sample_valid) begin
                if(cycle-auto_requested_at!=4 || auto_dut.sample_clipped!==0)
                    begin $display("FAIL: automatic R4/quiet mix contract failed"); $finish; end
                auto_previous=auto_dut.sample_data;
            end
        end
    end
    always @(posedge bck or negedge rst_n) begin
        if(!rst_n) begin words=0; bits=0; received=0; end
        else if(dut.audio_ready) begin
            if(ws!==(words%2)) begin $display("FAIL: ADSR wrong channel"); $finish; end
            if(dut.sample_underrun!==(words<2)) begin $display("FAIL: ADSR non-startup underrun"); $finish; end
            received={received[14:0],din}; bits=bits+1;
            if(bits==16) begin
`ifdef ADSR_NEGATIVE_CONTROL
                // 验证串行检查器确实能拒绝错误，不修改正式RTL。
                if((received ^ 16'h8000)!==expected[words/2]) begin $display("FAIL: intentional ADSR serial mutation"); $finish; end
`else
                if(received!==expected[words/2]) begin $display("FAIL: ADSR serial mismatch word %0d",words); $finish; end
`endif
                words=words+1; total=total+1; bits=0;
                if(received!=0) nonzero_words=nonzero_words+1;
            end
        end
    end
    always @(posedge abck or negedge rst_n) begin
        if(!rst_n) begin auto_words=0; auto_bits=0; auto_received=0; end
        else if(auto_dut.audio_ready) begin
            if(aws!==(auto_words%2) || auto_dut.sample_underrun!==(auto_words<2))
                begin $display("FAIL: automatic channel/underrun failed"); $finish; end
            auto_received={auto_received[14:0],adin}; auto_bits=auto_bits+1;
            if(auto_bits==16) begin
                if(auto_received!==auto_expected[auto_words/2])
                    begin $display("FAIL: automatic serial mismatch word %0d",auto_words); $finish; end
                if(auto_received!=0) auto_nonzero_words=auto_nonzero_words+1;
                auto_words=auto_words+1; auto_bits=0;
            end
        end
    end
    task wait_frames(input integer count);
        integer start;
        begin start=frames; wait(frames>=start+count); @(negedge clk); end
    endtask
    initial begin
        repeat(4) @(negedge clk);
        if(pa!==1 || apa!==1) begin $display("FAIL: ADSR unsafe reset amp"); $finish; end
        rst_n=1;
        @(posedge clk); #1; if(dut.audio_ready!==0) begin $display("FAIL: early ADSR reset release"); $finish; end
        @(posedge clk); #1; if(dut.audio_ready!==1) begin $display("FAIL: late ADSR reset release"); $finish; end
        wait_frames(5);
        if(pa!==1 || dut.voice_count!==0) begin $display("FAIL: ADSR idle not muted"); $finish; end
        keys=2; repeat(3) @(negedge clk); keys=3;
        repeat(20) @(negedge clk);
        if(dut.voice_count!==0) begin $display("FAIL: ADSR bounce note"); $finish; end
        keys=2; wait_frames(30);
        if(dut.voice_count!==1 || dut.voice_note_flat[6:0]!==60 || pa!==0)
            begin $display("FAIL: ADSR C4 not connected"); $finish; end
        keys=0; wait_frames(30);
        if(dut.voice_count!==2 || dut.voice_note_flat[13:7]!==64) begin $display("FAIL: ADSR chord failed"); $finish; end
        keys=1; wait_frames(4);
        if(dut.voice_count!==2 || pa!==0) begin $display("FAIL: ADSR release recycled early"); $finish; end
        keys=0; wait_frames(30); // 释放中重按，C应重新分配并触发包络。
        if(dut.voice_count!==2) begin $display("FAIL: ADSR re-press failed"); $finish; end
        keys=3; wait_frames(30);
        if(dut.voice_count!==0 || dut.sample_data!==0 || pa!==1) begin $display("FAIL: ADSR tail stuck"); $finish; end
        if(peak!=4 || auto_dut.voice_count!==0 || apa!==1) begin $display("FAIL: ADSR automatic four voices failed"); $finish; end
        keys=0; wait_frames(20);
        rst_n=0; #1;
        if(pa!==1 || bck!==1 || din!==0) begin $display("FAIL: ADSR unsafe midstream reset"); $finish; end
        repeat(4) @(negedge clk); rst_n=1;
        wait_frames(30);
        if(dut.voice_count!==2) begin $display("FAIL: ADSR held-key restart failed"); $finish; end
        keys=3; wait_frames(30);
        if(dut.voice_count!==0 || pa!==1 || total<400 || accepted<200 || triggers<5 ||
            nonzero_words<20 || auto_nonzero_words<20)
            begin $display("FAIL: incomplete ADSR integration coverage"); $finish; end
        $display("PASS tb_instrument_adsr: 50MHz/48kHz, R4 capture, LSBJ, keys, four voices, reset, release");
        $finish;
    end
    initial begin #15000000; begin $display("FAIL: ADSR instrument timeout"); $finish; end end
endmodule
