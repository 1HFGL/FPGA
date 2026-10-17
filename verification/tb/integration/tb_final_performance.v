`timescale 1ns/1ps
// 正式无屏入口：真实I2C节拍/转换等待、16声部、双音色、PC归属与DAC串行检查。
// 仅按键消抖和UART测试传输加速；不据此报告整机模拟延迟。
module tb_final_performance;
    reg clk=0,rst=0,rx=1;
    reg [1:0] board_keys=3;
    reg [12:0] keys=13'h1fff;
    tri1 sda;
    wire tx,bck,ws,din,pa,scl;
    always #10 clk=~clk;
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .UART_CLKS_PER_BIT(16)) dut(.sys_clk(clk),.sys_rst_n(rst),.Key_in(board_keys),
        .piano_key_n(keys),.uart_rx(rx),.uart_tx(tx),.HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),
        .PA_EN(pa),.knob_sda(sda),.knob_scl(scl));
    performance_adc_model #(.CONV0(26400),.CONV1(13200)) adc(.sda(sda),.scl(scl));
    integer frames=0,cycle=0,issue=0,words=0,bits=0,n,heard[0:15],serial_nonzero=0;
    reg [15:0] word=0,pending_sample=0,active_sample=0;
    reg pending_valid=0;
    reg [17:0] held_ratio;
    reg [16:0] held_gain;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!dut.core_ready)begin frames=0;issue=0;pending_sample<=0;active_sample<=0;pending_valid<=0;end
        else begin
            if(dut.u_core.sample_request)begin frames=frames+1;issue=cycle;end
            if(dut.u_core.sample_valid)begin
                if(cycle-issue!=924)begin $display("FAIL final R924 capture contract %0d",cycle-issue);$finish;end
                for(n=0;n<16;n=n+1)
                    if(dut.u_core.g_modal.u_bank.u_modal.last_voice[n]!=0)heard[n]=heard[n]+1;
            end
            if(frames>4 && (dut.u_core.sample_underrun || dut.u_core.g_modal.core_overrun))begin
                $display("FAIL final audio deadline frames=%0d underrun=%b overrun=%b",frames,dut.u_core.sample_underrun,dut.u_core.g_modal.core_overrun);$finish;end
            if(dut.u_core.output_frame_start)begin
                active_sample<=pending_valid?pending_sample:16'd0;pending_valid<=0;
            end
            if(dut.u_core.sample_valid)begin pending_sample<=dut.u_core.sample_data;pending_valid<=1;end
        end
    end
    always @(posedge bck)if(dut.core_ready)begin
        word={word[14:0],din};bits=bits+1;
        if(bits==16)begin
            bits=0;words=words+1;
            if(word!==active_sample)begin $display("FAIL final DAC word got=%h expected=%h",word,active_sample);$finish;end
            if(word!=0)serial_nonzero=serial_nonzero+1;
        end
    end
    task wait_frames;
        input integer count;integer f;
        begin f=frames;wait(frames>=f+count);@(negedge clk);end
    endtask
    task send;
        input [511:0] text;integer bytes,a,b,k;
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
    function integer held;
        input integer pc;integer j;
        begin held=0;for(j=0;j<16;j=j+1)
            if(dut.u_core.voice_key_down[j] && dut.u_core.voice_source_flat[j*8+7]==pc)held=held+1;
        end
    endfunction
    initial begin
        for(n=0;n<16;n=n+1)heard[n]=0;
        repeat(8)@(negedge clk);rst=1;
        wait(dut.param_ready && dut.knob_value_flat=={7'd64,7'd127});wait_frames(70);
        keys[0]=0;wait_frames(12);
        board_keys[0]=0;wait_frames(3);board_keys[0]=1;wait_frames(3);
        if(dut.u_core.voice_count!=1 || dut.u_core.monitor_piano_keys!==1)begin $display("FAIL final C4 alias");$finish;end
        board_keys[1]=0;wait_frames(8);
        if(!dut.u_core.monitor_instrument_guitar || dut.u_core.voice_count!=1)begin $display("FAIL final mode hold");$finish;end
        board_keys[1]=1;keys=0;wait_frames(15);
        if(dut.u_core.monitor_piano_keys!==1 || dut.u_core.monitor_guitar_keys!==13'h1ffe)begin $display("FAIL final per-instrument held notes");$finish;end
        send("HELLO\n");send("NOTE_ON 84 100 0\n");send("NOTE_ON 85 100 0\n");send("NOTE_ON 86 100 0\n");
        wait_frames(40);
        if(dut.u_core.voice_count!=16 || held(0)!=13 || held(1)!=3)begin $display("FAIL final 16 physical/PC voices");$finish;end
        for(n=0;n<16;n=n+1)if(heard[n]<10)begin $display("FAIL final silent modal voice %0d",n);$finish;end
        send("NOTE_ON 87 100 0\n");wait_frames(8);
        if(dut.u_core.voice_count!=16 || dut.u_core.steal_count!=1)begin $display("FAIL final 17th note steal");$finish;end
        keys[0]=1;wait_frames(8);
        if(held(1)!=4)begin $display("FAIL old physical release killed stolen PC voice");$finish;end
        // 真I2C参数走到A的实际请求快照，不观察未采用的兼容合成路径。
        adc.conversion0=0;wait(dut.knob_value_flat[6:0]==0);wait_frames(70);
        if(dut.u_core.sample_data!==0 || dut.u_core.g_modal.u_bank.u_modal.gain_latched!==0)begin $display("FAIL final actual PCM mute");$finish;end
        adc.conversion0=26400;adc.conversion1=26400;
        wait(dut.knob_value_flat=={7'd127,7'd127});wait_frames(70);
        if(dut.u_core.g_modal.u_bank.u_modal.ratio_latched!==73562 ||
           dut.u_core.g_modal.u_bank.u_modal.gain_latched!==65536)begin $display("FAIL final actual modal global controls");$finish;end
        held_ratio=dut.u_core.bend_ratio;held_gain=dut.u_core.master_gain;
        adc.connected=0;wait(dut.param_fault);wait_frames(70);
        if(dut.u_core.master_gain!==held_gain || dut.u_core.bend_ratio!==held_ratio)begin $display("FAIL final ADC fault hold");$finish;end
        adc.conversion1=13200;adc.connected=1;
        wait(dut.param_ready && !dut.param_fault && dut.knob_value_flat=={7'd64,7'd127});wait_frames(70);
        if(dut.u_core.g_modal.u_bank.u_modal.ratio_latched!==65536)begin $display("FAIL final ADC recovery");$finish;end
        send("PANIC\n");wait_frames(4300);
        if(held(1)!=0 || held(0)!=12 || dut.u_core.voice_count!=12)begin $display("FAIL final source-specific panic");$finish;end
        keys=13'h1fff;wait_frames(4300);
        if(dut.u_core.voice_count!=0 || pa!==1 || serial_nonzero<100)begin $display("FAIL final tail/PA drain");$finish;end
        @(negedge clk);rst=0;bits=0;word=0;repeat(8)@(negedge clk);
        // 复位增益合同为满音量 65536（与既有 tb_performance_adc 一致），
        // 不按音色模式改动上电首个采样。
        if(dut.u_core.master_gain!==65536 || dut.u_core.bend_ratio!==65536 || pa!==1)begin $display("FAIL final safe reset");$finish;end
        rst=1;wait_frames(8);
        if(dut.u_core.monitor_instrument_guitar || dut.u_core.voice_count!=0)begin $display("FAIL final reset mode/ownership");$finish;end
        $display("PASS tb_final_performance: 16 nonzero modal voices, actual I2C mute/bend/fault/recovery, mode/owners/steal, R924, %0d exact DAC words",words);$finish;
    end
    initial begin #300000000;$display("FAIL final performance timeout");$finish;end
endmodule
