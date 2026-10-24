`timescale 1ns/1ps
// 两个真实8N1输入/回包，独立会话，共用16声部与正式模态三效果链。
// 缩短UART位时间/看门狗用于仿真；不是实物BLE无线链路或延迟验收。
module tb_ble_link;
    reg clk=0,rst_n=0,pc_rx=1,ble_rx=1,state=0;
    reg [1:0] key_in=3;
    reg [12:0] keys=13'h1fff;
    wire pc_tx,ble_tx,ready;
    always #10 clk=~clk;
    instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .FIXED_PIANO(1),.VOICES(16),.EXTERNAL_PIANO_KEYS(1),.ENABLE_CONTROLS(1),
        .ENABLE_GUITAR(1),.ENABLE_OCTAVE_KEY(1),.ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),
        .USE_MODAL(1),.REQUEST_LEAD_HALF_EDGES(60),.ENABLE_CHORUS(1),.ENABLE_DELAY(1),.ENABLE_REVERB(1),
        .ENABLE_BLE(1),.UART_CLKS_PER_BIT(16),.BLE_CLKS_PER_BIT(40),.WATCHDOG_CYCLES(450000)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(key_in),.piano_key_n(keys),
        .uart_rx(pc_rx),.uart_tx(pc_tx),.ble_rx(ble_rx),.ble_tx(ble_tx),.ble_state(state),
        .HP_BCK(),.HP_WS(),.HP_DIN(),.PA_EN(),.knob_value_flat({7'd64,7'd127}),
        .knob_valid(1'b1),.param_ready(1'b1),.param_fault(1'b0),.control_sustain(1'b0),
        .control_octave(2'd1),.control_brightness(7'd127),.control_ready(ready),
        .monitor_audio_valid(),.monitor_audio_sample(),.monitor_key_down(),.monitor_instrument_guitar(),
        .monitor_piano_keys(),.monitor_guitar_keys(),.monitor_octave(),.monitor_brightness());
    wire [7:0] pc_byte,ble_byte;
    wire pc_valid,ble_valid,pc_bad,ble_bad;
    uart_rx #(.CLKS_PER_BIT(16)) pc_monitor(.clk(clk),.rst_n(rst_n),.rx(pc_tx),.data(pc_byte),.valid(pc_valid),.frame_error(pc_bad));
    uart_rx #(.CLKS_PER_BIT(40)) ble_monitor(.clk(clk),.rst_n(rst_n),.rx(ble_tx),.data(ble_byte),.valid(ble_valid),.frame_error(ble_bad));
    reg [2047:0] pc_line=0,ble_line=0;
    integer pc_length=0,ble_length=0,pc_hello=0,ble_hello=0,pc_replies=0,ble_replies=0;
    integer cycle=0,issue=0,samples=0,nonzero=0,pc_saved,n;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(ready)begin
            if(dut.sample_request)issue=cycle;
            if(dut.output_sample_valid)begin
                if(cycle-issue!=953)begin $display("FAIL BLE R953 cache contract output_valid=%0d",cycle-issue);$stop;end
                samples=samples+1;if(dut.output_sample_data!=0)nonzero=nonzero+1;
            end
            // DAC首帧空缓存是既有启动合同；稳态以后不允许任何欠载/过载。
            if(samples>4 && (dut.sample_underrun || dut.g_modal.core_overrun || dut.tone_overrun || dut.chorus_overrun || dut.delay_overrun || dut.reverb_overrun))begin
                $display("FAIL BLE disturbed audio deadline frames=%0d flags=%b%b%b%b%b%b",samples,dut.sample_underrun,dut.g_modal.core_overrun,dut.tone_overrun,dut.chorus_overrun,dut.delay_overrun,dut.reverb_overrun);$stop;end
        end
        if(pc_bad || ble_bad)begin $display("FAIL BLE reply framing");$stop;end
        if(pc_valid)begin
            pc_line={pc_line[2039:0],pc_byte};pc_length=pc_length+1;
            if(pc_byte==10)begin
                if(pc_length>=7 && (pc_line>>((pc_length-7)*8))=="SYNTH/1")pc_hello=pc_hello+1;
                pc_replies=pc_replies+1;pc_line=0;pc_length=0;
            end
        end
        if(ble_valid)begin
            ble_line={ble_line[2039:0],ble_byte};ble_length=ble_length+1;
            if(ble_byte==10)begin
                if(ble_length>=7 && (ble_line>>((ble_length-7)*8))=="SYNTH/1")ble_hello=ble_hello+1;
                ble_replies=ble_replies+1;ble_line=0;ble_length=0;
            end
        end
    end
    function integer held;
        input [1:0] group;
        integer j;
        begin held=0;for(j=0;j<16;j=j+1)
            if(dut.voice_key_down[j] && dut.voice_source_flat[j*9+7+:2]==group)held=held+1;
        end
    endfunction
    task automatic send;
        input channel;
        input [511:0] text;
        integer bytes,a,b,j,period;
        begin
            period=channel?40:16;bytes=0;
            for(j=0;j<64;j=j+1)if(text[j*8+:8]!=0)bytes=j+1;
            for(a=bytes-1;a>=0;a=a-1)begin
                @(negedge clk);if(channel)ble_rx=0;else pc_rx=0;
                repeat(period)@(negedge clk);
                for(b=0;b<8;b=b+1)begin
                    if(channel)ble_rx=text[a*8+b];else pc_rx=text[a*8+b];
                    repeat(period)@(negedge clk);
                end
                if(channel)ble_rx=1;else pc_rx=1;
                repeat(period)@(negedge clk);
            end
            repeat(100)@(negedge clk);
        end
    endtask
    task check_held;
        input integer physical,pc,ble;
        begin
            repeat(2500)@(negedge clk);
            if(held(0)!=physical || held(2)!=pc || held(3)!=ble)begin
                $display("FAIL BLE source isolation got %0d/%0d/%0d expected %0d/%0d/%0d",held(0),held(2),held(3),physical,pc,ble);$stop;end
        end
    endtask
    initial begin
        repeat(10)@(negedge clk);rst_n=1;wait(ready);
        keys[0]=0;state=1;
        fork send(0,"HELLO\n");send(1,"HELLO\n");join
        wait(pc_hello==1 && ble_hello==1);
        fork send(0,"NOTE_ON 60 100 0\n");send(1,"NOTE_ON 60 100 0\n");join
        check_held(1,1,1);
        send(1,"NOTE_ON 64 100 0\n");check_held(1,1,2);
        send(1,"NOTE_OFF 60 0\n");check_held(1,1,1);
        send(1,"HELLO\n");wait(ble_hello==2);check_held(1,1,0);
        send(1,"NOTE_ON 60 100 0\n");check_held(1,1,1);
        send(0,"PANIC\n");check_held(1,0,1);
        send(0,"NOTE_ON 62 100 0\n");check_held(1,1,1);
        // 断连发生在半条命令之后，快速重连的首条HELLO必须成功。
        send(1,"NOTE_ON 67 ");state=0;check_held(1,1,0);
        repeat(200)@(negedge clk);state=1;repeat(10)@(negedge clk);
        send(1,"HELLO\n");wait(ble_hello==3);
        send(1,"NOTE_ON 65 100 0\n");check_held(1,1,1);
        // PC会话持续心跳；BLE无消息到超时，只能清BLE声部。
        fork
            begin while(dut.g_ble.u_protocol.session_ready)begin
                send(0,"STATUS?\n");repeat(50000)@(negedge clk);
            end end
            begin wait(!dut.g_ble.u_protocol.session_ready);end
        join
        check_held(1,1,0);
        // 重新握手能恢复演奏；KEY2仍影响新音，已有声部不改音色。
        send(1,"HELLO\n");wait(ble_hello==4);key_in[1]=0;repeat(40)@(negedge clk);key_in[1]=1;
        send(1,"NOTE_ON 67 100 0\n");check_held(1,1,1);
        if(!dut.monitor_instrument_guitar)begin $display("FAIL BLE preserved mode key");$stop;end
        for(n=0;n<16;n=n+1)if(dut.voice_key_down[n] && dut.voice_source_flat[n*9+7+:2]==3 && !dut.voice_timbre_flat[n*4])begin
            $display("FAIL BLE timbre of new voice");$stop;end
        keys=13'h1fff;send(1,"PANIC\n");send(0,"PANIC\n");check_held(0,0,0);
        if(samples<300 || nonzero<100 || pc_hello<1 || ble_hello<4)begin
            $display("FAIL BLE coverage samples=%0d nonzero=%0d hello=%0d/%0d",samples,nonzero,pc_hello,ble_hello);$stop;end
        $display("PASS tb_ble_link: independent HELLO/replies; same-pitch polyphony; NOTE_OFF/PANIC/source cleanup; partial-line disconnect/reconnect; BLE watchdog; mode/audio R953 samples=%0d",samples);$finish;
    end
    initial begin #50000000;$display("FAIL BLE global timeout pcHello=%0d bleHello=%0d",pc_hello,ble_hello);$stop;end
endmodule
