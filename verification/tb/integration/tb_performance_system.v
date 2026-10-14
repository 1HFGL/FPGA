`timescale 1ns/1ps
// 真实50MHz/48kHz比例：实体与UART共享16声部、全局控制、尾音和串行输出。
// 只缩短按键消抖/包络/UART，延迟是数字观察，不含机械抖动及DAC模拟响应。
module tb_performance_system;
    reg clk=0,rst_n=0,rx=1;
    reg [12:0] keys=13'h1fff;
    reg [13:0] knobs={7'd64,7'd127};
    reg kv=0,sustain=0;
    reg [1:0] octave=1;
    wire tx,bck,ws,din,pa;
    integer frames=0,nonzero=0,bits=0,v,n,limit,start_cycle=0,cycle=0,first_pcm=0,first_dac=0;
    integer heard[0:15];
    reg [15:0] word=0;
    reg signed [33:0] expected_product;
    reg signed [15:0] expected_output;
    instrument_uart_top #(.VOICES(16),.ENABLE_CONTROLS(1),.EXTERNAL_PIANO_KEYS(1),
        .DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16),.WATCHDOG_CYCLES(150000000),
        .ROM_FILE("rtl/rom/piano_1024.mem"),.ATTACK_SAMPLES(4),.DECAY_SAMPLES(4),
        .SUSTAIN_LEVEL(65536),.RELEASE_SAMPLES(32),.REQUEST_LEAD_HALF_EDGES(2)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(keys),.uart_rx(rx),.uart_tx(tx),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_value_flat(knobs),
        .knob_valid(kv),.param_ready(1'b1),.param_fault(1'b0),.control_sustain(sustain),.control_octave(octave),.control_ready());
    always #10 clk=~clk;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(dut.audio_ready && dut.sample_request)frames=frames+1;
        if(dut.audio_ready && frames>4 && dut.sample_underrun)begin $display("FAIL: frame underrun");$finish;end
        if(start_cycle!=0 && first_pcm==0 && dut.sample_valid && dut.sample_data!=0)first_pcm=cycle;
        if(dut.bank_sample_valid)begin
            for(v=0;v<16;v=v+1)
                if($signed(dut.u_bank.gain_samples[v*16+:16])!=0)heard[v]=heard[v]+1;
        end
        // 直接检验主工程末级音量乘法的真实输出，不仅检查控制寄存器。
        if(dut.audio_ready && dut.bank_sample_valid) begin
            expected_product=$signed(dut.bank_sample_data)*$signed({1'b0,dut.g_controls.gain_d4});
            expected_output=expected_product>>>16;
            #1;
            if(dut.sample_data!==expected_output) begin
                $display("FAIL: master gain not connected in top got=%0d expected=%0d",dut.sample_data,expected_output);$finish;
            end
        end
    end
    always @(posedge bck)if(dut.audio_ready)begin
        word={word[14:0],din};bits=bits+1;
        if(bits==16)begin
            bits=0;
            if(word!=0)begin
                nonzero=nonzero+1;
                if(start_cycle!=0 && first_dac==0 && !ws)first_dac=cycle;
            end
        end
    end
    task wait_frames;
        input integer count;
        integer f;
        begin f=frames;wait(frames>=f+count);@(negedge clk);end
    endtask
    task send;
        input [511:0] text;
        integer bytes,a,b,k;
        begin
            bytes=0;for(k=0;k<64;k=k+1)if(text[k*8+:8]!=0)bytes=k+1;
            for(a=bytes-1;a>=0;a=a-1)begin
                @(negedge clk);rx=0;repeat(16)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
                rx=1;repeat(16)@(negedge clk);
            end
            repeat(40)@(negedge clk);
        end
    endtask
    task set_knobs;
        input [6:0] volume,bend;
        begin @(negedge clk);knobs={bend,volume};kv=1;@(negedge clk);kv=0;wait_frames(70);end
    endtask
    function integer held;
        input integer pc;
        integer j;
        begin held=0;for(j=0;j<16;j=j+1)
            if(dut.u_allocator.voice_key_down[j] && dut.voice_source_flat[j*8+7]==pc)held=held+1;end
    endfunction
    initial begin
        for(n=0;n<16;n=n+1)heard[n]=0;
        repeat(8)@(negedge clk);rst_n=1;wait_frames(5);
        @(negedge clk);start_cycle=cycle;keys[0]=0;
        wait(first_dac!=0);
        if(first_dac-start_cycle>5000)begin $display("FAIL: digital onset");$finish;end
        send("HELLO\n");send("NOTE_ON 60 100 0\n");
        wait_frames(8);
        if(dut.voice_count!=2 || held(0)!=1 || held(1)!=1)begin $display("FAIL: same pitch ownership");$finish;end
        send("NOTE_OFF 60 0\n");wait_frames(40);
        if(dut.voice_count!=1 || held(0)!=1)begin $display("FAIL: PC off closed local");$finish;end
        sustain=1;keys[0]=1;wait_frames(6);
        if(dut.voice_count!=1 || dut.voice_gate==0)begin $display("FAIL: sustain not held");$finish;end
        sustain=0;wait_frames(40);if(dut.voice_count!=0)begin $display("FAIL: sustain release");$finish;end
        keys[0]=0;wait_frames(5);octave=2;keys[0]=1;wait_frames(40);
        if(dut.voice_count!=0)begin $display("FAIL: octave release mismatch");$finish;end
        keys[0]=0;wait_frames(5);
        if(dut.voice_note_flat[6:0]!=72)begin $display("FAIL: octave new note");$finish;end
        keys=13'h1fff;octave=1;wait_frames(40);
        for(n=0;n<16;n=n+1)heard[n]=0;
        keys=0;wait_frames(8);
        send("NOTE_ON 84 100 0\n");send("NOTE_ON 85 100 0\n");send("NOTE_ON 86 100 0\n");
        wait_frames(30);
        if(dut.voice_count!=16 || held(0)!=13 || held(1)!=3)begin $display("FAIL: sixteen voices");$finish;end
        for(n=0;n<16;n=n+1)if(heard[n]<10)begin $display("FAIL: silent top voice %0d",n);$finish;end
        send("NOTE_ON 87 100 0\n");wait_frames(5);
        if(dut.voice_count!=16 || dut.steal_count!=1)begin $display("FAIL: seventeenth steal");$finish;end
        set_knobs(64,127);
        if(dut.bend_ratio!=73562 || dut.master_gain!=33026)begin $display("FAIL: top controls");$finish;end
        set_knobs(0,64);
        if(dut.sample_data!==0)begin $display("FAIL: top mute");$finish;end
        set_knobs(127,64);
        // PC清理跳过延音，只释放PC；不误关13实体键的其他音。
        sustain=1;send("PANIC\n");wait_frames(40);
        if(held(1)!=0 || held(0)!=12 || dut.voice_count!=12)begin $display("FAIL: panic source/sustain");$finish;end
        send("NOTE_ON 88 100 0\n");send("NOTE_ON 89 100 0\n");wait_frames(5);
        // 受控故障注入检验整机清理范围；正式RTL的故障来源是事件队列溢出。
        force dut.u_key_events.input_overflow=1'b1;
        wait_frames(40);
        if(held(0)!=0 || held(1)!=2 || dut.voice_count!=2)begin $display("FAIL: local fault damaged PC or sustained local voice");$finish;end
        release dut.u_key_events.input_overflow;
        send("PANIC\n");sustain=0;keys=13'h1fff;wait_frames(40);
        if(dut.voice_count!=0 || pa!==1 || nonzero<100)begin $display("FAIL: drain/output");$finish;end
        @(negedge clk);rst_n=0;repeat(5)@(negedge clk);
        if(dut.voice_count!=0 || dut.sample_data!==0 || pa!==1)begin $display("FAIL: reset");$finish;end
        $display("PASS tb_performance_system: 13keys+UART/16 sounding voices/steal/sources/octave/sustain/volume/bend/DAC; digital_onset=%0dns",20*(first_dac-start_cycle));
        $finish;
    end
    initial begin #100000000;$display("FAIL: system timeout");$finish;end
endmodule
