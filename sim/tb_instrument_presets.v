`timescale 1ns/1ps
// 用真实50MHz/48kHz节拍核对板级串行链路；只缩短消抖和包络时长。
// 数字波形和ADSR数学本体由tb_instrument_bank独立逐点验证，本测试补接口/板级行为。
module tb_instrument_presets;
    reg clk=0, rst_n=1;
    reg [1:0] keys=2'b11;
    wire bck, ws, din, pa;
    localparam integer GR=24, SR=40;
    instrument_presets_top #(
        .DEBOUNCE_CYCLES(8),
        .G_ATTACK(4),.G_DECAY(20),.G_SUSTAIN(0),.G_RELEASE(GR),
        .S_ATTACK(12),.S_DECAY(16),.S_SUSTAIN(49152),.S_RELEASE(SR),
        .G_TONE_SAMPLES(16),.S_TONE_SAMPLES(24)
    ) dut (.sys_clk(clk),.sys_rst_n(rst_n),.Key_in(keys),
           .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    always #10 clk=~clk;

    reg [15:0] expected[0:4095], previous_mix=0, received=0;
    reg [15:0] captured_sample;
    reg capture_valid, observed_bit;
    reg [4:0] request_pipe=0;
    integer frames=0, words=0, bits=0, total_words=0;
    integer clocks=0, last_request=0, last_edge=0, interval;
    integer outputs=0, positive=0, negative=0, buffered=0, transitions=0;
    integer starts=0, presses=0, toggles=0, serial_nonzero=0;
    integer before_start, before_press, before_toggle, i;
    reg have_edge=0;

    // R0为请求，R4才允许新输出，B在下一拍R5捕获；帧始终使用上一帧完成的样本。
    always @(posedge clk) begin
        clocks=clocks+1;
        if(!dut.audio_ready) begin
            frames=0; previous_mix=0; last_request=0; request_pipe=0;
            capture_valid=0; captured_sample=0;
        end else begin
            if(dut.sample_request) begin
                if(frames>=4096) begin $display("FAIL: frame scoreboard full"); $finish; end
                expected[frames]=previous_mix;
                if(last_request) begin
                    interval=clocks-last_request;
                    if(interval!=1041 && interval!=1042) begin $display("FAIL: incorrect 48kHz frame interval"); $finish; end
                end
                last_request=clocks; frames=frames+1;
            end
            if(dut.voice_retrigger[0]) presses=presses+1;
            if(dut.key_press[1]) toggles=toggles+1;
            if(dut.u_bank.g_voice[0].u_voice.start_note) starts=starts+1;
            capture_valid=dut.sample_valid;
            captured_sample=dut.sample_data;
            if(capture_valid) previous_mix=captured_sample;
            request_pipe={request_pipe[3:0],dut.sample_request};
        end
        #1;
        if(dut.sample_valid!==request_pipe[4]) begin $display("FAIL: R4 sample_valid is early/late"); $finish; end
        if(dut.sample_clipped!==0) begin $display("FAIL: single quiet voice unexpectedly clipped"); $finish; end
        if(dut.voice_gate[3:1]!==0 || dut.voice_retrigger[3:1]!==0 ||
           dut.voice_active[3:1]!==0 || dut.env_level_flat[67:17]!==0)
            begin $display("FAIL: unused voices are active"); $finish; end
        if(capture_valid) begin
            if(dut.u_b.u_i2s_tx.pending_sample!==captured_sample ||
               dut.u_b.u_i2s_tx.pending_valid!==1)
                begin $display("FAIL: R5 output cache did not capture matching R4 sample"); $finish; end
            buffered=buffered+1;
        end
        if(dut.sample_valid) begin
            outputs=outputs+1;
            if($signed(dut.sample_data)>0) positive=positive+1;
            if($signed(dut.sample_data)<0) negative=negative+1;
        end
    end

    // 检查分数分频的每个半周期；这属于逻辑协议测试，不替代DAC板级建立/保持测量。
    always @(bck or negedge rst_n) begin
        if(!rst_n || !dut.audio_ready) begin have_edge=0; last_edge=0; end
        else begin
            if(have_edge && clocks-last_edge!=16 && clocks-last_edge!=17)
                begin $display("FAIL: BCK half cycle must be 16 or 17 sys_clk cycles"); $finish; end
            have_edge=1; last_edge=clocks; transitions=transitions+1;
        end
    end
    always @(ws or din) if(rst_n && dut.audio_ready && bck!==0)
        begin $display("FAIL: WS/DIN changed outside the BCK falling phase"); $finish; end

    // 从引脚重新解码16位LSBJ：WS=0右、WS=1左，无Philips格式的一位空隙。
    always @(posedge bck or negedge rst_n) begin
        if(!rst_n) begin words=0; bits=0; received=0; end
        else if(dut.audio_ready) begin
            if(ws!==(words%2)) begin $display("FAIL: incorrect LSBJ channel"); $finish; end
            if(dut.sample_underrun!==(words<2)) begin $display("FAIL: underrun after startup frame"); $finish; end
            observed_bit=din;
`ifdef PRESETS_BOARD_NEGATIVE_CONTROL
            if(words==0 && bits==0) observed_bit=~observed_bit;
`endif
            received={received[14:0],observed_bit}; bits=bits+1;
            if(expected[words/2]!=0 && pa!==0)
                begin $display("FAIL: PA disabled before nonzero serial tail was sent"); $finish; end
            if(bits==16) begin
                if(received!==expected[words/2])
                    begin $display("FAIL: serial mismatch word=%0d expected=%h actual=%h",words,expected[words/2],received); $finish; end
                if(received!=0) serial_nonzero=serial_nonzero+1;
                words=words+1; total_words=total_words+1; bits=0;
            end
        end
    end

    task wait_frames(input integer count);
        integer start;
        begin start=frames; wait(frames>=start+count); @(negedge clk); end
    endtask
    task set_keys(input reg [1:0] value);
        begin
@(negedge clk); keys=value;
        end
    endtask
    task wait_clocks(input integer count);
        begin
repeat(count) @(negedge clk);
        end
    endtask
    task check_quiet;
        begin
            if(dut.voice_gate!==0 || dut.voice_active!==0 || dut.release_done!==15 ||
               dut.sample_data!==0 || dut.sounding!==0 || pa!==1)
                begin $display("FAIL: final release/cache drain did not mute"); $finish; end
        end
    endtask
    task check_one_start;
        begin
if(starts-before_start!=1 || presses-before_press!=1)
            begin $display("FAIL: one KEY1 press caused %0d starts/%0d pulses",starts-before_start,presses-before_press); $finish; end
        end
    endtask

    initial begin
        #1; rst_n=0; // 显式产生异步复位沿，避免模拟器初始X调度差异。
        wait_clocks(4);
        if(pa!==1 || bck!==1 || din!==0) begin $display("FAIL: unsafe initial reset"); $finish; end
        rst_n=1;
        @(posedge clk); #2; if(dut.audio_ready!==0) begin $display("FAIL: early reset release"); $finish; end
        @(posedge clk); #2; if(dut.audio_ready!==1) begin $display("FAIL: late reset release"); $finish; end
        wait_frames(5); check_quiet();
        if(dut.selected_instrument!==0) begin $display("FAIL: default is not guitar"); $finish; end

        // 两个按键的短抖动均不得生成事件。
        before_start=starts; before_press=presses; before_toggle=toggles;
        set_keys(2'b10); wait_clocks(3); set_keys(2'b11); wait_clocks(24);
        set_keys(2'b01); wait_clocks(3); set_keys(2'b11); wait_clocks(24);
        wait_frames(2);
        if(starts!=before_start || presses!=before_press || toggles!=before_toggle ||
           dut.selected_instrument!==0) begin $display("FAIL: bounce created an event"); $finish; end
        check_quiet();

        before_start=starts; before_press=presses;
        set_keys(2'b10); wait_frames(8); check_one_start();
        if(dut.voice_gate!==1 || dut.instrument_active!==0 || pa!==0)
            begin $display("FAIL: KEY1 did not start guitar"); $finish; end
        // 持续按住KEY2只翻转一次，已经响起的拨弦保留原预设。
        before_toggle=toggles;
        set_keys(2'b00); wait_frames(45);
        if(toggles-before_toggle!=1 || dut.selected_instrument!==1 || dut.instrument_active!==0)
            begin $display("FAIL: held KEY2 repeats or changes held voice"); $finish; end
        set_keys(2'b10); wait_frames(2);
        set_keys(2'b11); wait_frames(GR+8); check_quiet();

        before_start=starts; before_press=presses;
        set_keys(2'b10); wait_frames(50); check_one_start();
        if(dut.instrument_active!==1 || dut.env_level_flat[16:0]!==49152 || pa!==0)
            begin $display("FAIL: strings sustain missing"); $finish; end
        set_keys(2'b00); wait_frames(5);
        if(dut.selected_instrument!==0 || dut.instrument_active!==1)
            begin $display("FAIL: held strings changed on selection"); $finish; end
        set_keys(2'b10); wait_frames(2);
        set_keys(2'b11); wait_frames(2);
        if(dut.env_level_flat[16:0]==0 || dut.release_done[0]!==0 || pa!==0)
            begin $display("FAIL: strings release cut off early"); $finish; end
        // 尾音中两次选择变化，不能重置包络或替换旧乐器。
        set_keys(2'b01); wait_frames(2);
        set_keys(2'b11); wait_frames(2);
        set_keys(2'b01); wait_frames(2);
        if(dut.selected_instrument!==0 || dut.instrument_active!==1 || pa!==0)
            begin $display("FAIL: tail preset changed"); $finish; end
        wait_frames(SR+8); check_quiet();
        set_keys(2'b11); wait_frames(2);

        // 两键同拍按下，应采用翻转后的弦乐，而不是旧拨弦。
        before_start=starts; before_press=presses;
        set_keys(2'b00); wait_frames(4); check_one_start();
        if(dut.selected_instrument!==1 || dut.instrument_active!==1)
            begin $display("FAIL: simultaneous press did not use new selection"); $finish; end
        set_keys(2'b10); wait_frames(2);
        set_keys(2'b00); wait_frames(2);
        set_keys(2'b10); wait_frames(2);
        if(dut.selected_instrument!==0 || dut.instrument_active!==1)
            begin $display("FAIL: pre-retrigger selection setup failed"); $finish; end
        // 松开再按下均发生于两个采样请求之间，gate采样仍为高，靠trigger重起音。
        before_start=starts; before_press=presses;
        set_keys(2'b11); wait_clocks(24);
        set_keys(2'b10); wait_clocks(24);
        wait_frames(3); check_one_start();
        if(dut.instrument_active!==0) begin $display("FAIL: between-sample retrigger lost"); $finish; end
        set_keys(2'b11); wait_frames(GR+8); check_quiet();

        // 先按KEY1、后按KEY2，均在同一请求间隙；新音应记住KEY1当拍的拨弦。
        before_start=starts; before_press=presses;
        set_keys(2'b10); wait_clocks(24);
        set_keys(2'b00); wait_clocks(24);
        wait_frames(3); check_one_start();
        if(dut.selected_instrument!==1 || dut.instrument_active!==0)
            begin $display("FAIL: pending note selection snapshot was overwritten"); $finish; end

        // 扫描消抖完成落在采样边界前后的9个相位，防止level先变而press后到造成双起音。
        for(i=0;i<9;i=i+1) begin
            set_keys(2'b11); wait_frames(SR+8); check_quiet();
            before_start=starts; before_press=presses;
            while(clocks-last_request<1026+i) @(negedge clk);
            keys=2'b10;
            wait_frames(3); check_one_start();
        end
        set_keys(2'b00); wait_clocks(24);
        // 运行中复位立即关输出；两键保持按下，释放复位后各产生一次事件。
        rst_n=0; #1;
        if(pa!==1 || bck!==1 || din!==0) begin $display("FAIL: unsafe mid-stream reset"); $finish; end
        wait_clocks(4); before_start=starts; before_press=presses; before_toggle=toggles;
        rst_n=1; wait_frames(5); check_one_start();
        if(toggles-before_toggle!=1 || dut.selected_instrument!==1 || dut.instrument_active!==1)
            begin $display("FAIL: held keys after reset failed"); $finish; end
        set_keys(2'b11); wait_frames(SR+8); check_quiet();
        if(total_words<500 || outputs<250 || positive==0 || negative==0 ||
           buffered<250 || transitions<15000 || serial_nonzero==0 || starts<6)
            begin $display("FAIL: insufficient board integration coverage"); $finish; end
        $display("PASS: tb_instrument_presets %0d serial words, %0d outputs, +%0d/-%0d samples, %0d R5 captures; KEY1/KEY2, preset snapshots, R4, LSBJ, PA drain, reset.",
                 total_words,outputs,positive,negative,buffered);
        $finish;
    end
    initial begin #30000000; begin $display("FAIL: presets board timeout"); $finish; end end
endmodule
