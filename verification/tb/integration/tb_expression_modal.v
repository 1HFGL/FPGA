`timescale 1ns/1ps
// Current modal bank, real 50MHz/48kHz. Only debounce/UART/long-press are accelerated.
module tb_expression_modal;
    reg clk=0,rst=0,rx=1,kv=0;
    reg [1:0] bk=3;
    reg [12:0] keys=13'h1fff;
    reg [13:0] knobs={7'd64,7'd127};
    wire bck,ws,din,pa;
    integer frames=0,cycle=0,issue=0,fd,n,bits=0,words=0,nonzero=0;
    reg [15:0] word=0,pending=0,active=0,left_word=0,right_word=0;
    reg pending_valid=0;
    reg [16:0] prior_gain;
    reg [17:0] prior_bend;
    instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .UART_CLKS_PER_BIT(16),.WATCHDOG_CYCLES(150000000),.EXTERNAL_PIANO_KEYS(1),
        .VOICES(16),.ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),.USE_MODAL(1),
        .ENABLE_BRIGHTNESS(1),.BRIGHTNESS_REPEAT_CYCLES(50000),.REQUEST_LEAD_HALF_EDGES(60)) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.uart_tx(),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_value_flat(knobs),.knob_valid(kv),
        .param_ready(1'b1),.param_fault(1'b0),.control_sustain(1'b0),.control_octave(2'd1),
        .control_ready(),.monitor_audio_valid(),.monitor_audio_sample(),.monitor_key_down(),
        .monitor_instrument_guitar(),.monitor_piano_keys(),.monitor_guitar_keys());
    always #10 clk=~clk;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(dut.audio_ready)begin
            if(dut.sample_request)begin frames=frames+1;issue=cycle;end
            if(frames>4 && (dut.sample_underrun || dut.g_modal.core_overrun || dut.tone_overrun))
                begin $display("FAIL modal expression deadline");$finish;end
            if(dut.output_frame_start)begin active<=pending_valid?pending:16'd0;pending_valid<=0;end
            if(dut.output_sample_valid)begin
                if(cycle-issue!=927)begin $display("FAIL expression R927 got=%0d",cycle-issue);$finish;end
                pending<=dut.output_sample_data;pending_valid<=1;
                $fwrite(fd,"%0d,%0d,%0d,%0d\n",frames,$signed(dut.sample_data),dut.brightness_current,$signed(dut.output_sample_data));
                if(dut.output_sample_data!=0)nonzero=nonzero+1;
                if(dut.monitor_audio_valid!==1 || dut.monitor_audio_sample!==dut.output_sample_data)
                    begin $display("FAIL display must observe filtered sample");$finish;end
            end
        end
        #1;if(dut.audio_ready && pa && (left_word!=0 || right_word!=0))begin $display("FAIL modal PA tail");$finish;end
    end
    always @(posedge bck)if(dut.audio_ready)begin
        word={word[14:0],din};bits=bits+1;
        if(bits==16)begin
            bits=0;words=words+1;
            if(ws)left_word=word;else right_word=word;
            if(word!==active)begin $display("FAIL modal expression DAC %h %h",word,active);$finish;end
        end
    end
    task wait_frames;input integer count;integer start;
        begin start=frames;wait(frames>=start+count);@(negedge clk);end
    endtask
    task short_key;input integer key;
        begin bk[key]=0;repeat(200)@(negedge clk);bk[key]=1;repeat(200)@(negedge clk);end
    endtask
    task set_knob;input [6:0] vol,bend;
        begin knobs={bend,vol};kv=1;@(negedge clk);kv=0;wait_frames(150);end
    endtask
    task send;input [511:0] text;integer bytes,a,b,j;
        begin
            bytes=0;for(j=0;j<64;j=j+1)if(text[j*8+:8]!=0)bytes=j+1;
            for(a=bytes-1;a>=0;a=a-1)begin
                @(negedge clk);rx=0;repeat(16)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
                rx=1;repeat(16)@(negedge clk);
            end repeat(40)@(negedge clk);
        end
    endtask
    initial begin
        fd=$fopen("build/expression/modal_brightness.csv","w");
        $fwrite(fd,"frame,raw,brightness,filtered\n");
        repeat(8)@(negedge clk);rst=1;wait_frames(8);
        short_key(0);wait_frames(30);
        if(dut.brightness_current!=111 || dut.voice_count!=0 || dut.selected_guitar)
            begin $display("FAIL KEY1 aliases/mode");$finish;end
        for(n=0;n<7;n=n+1)short_key(0);wait_frames(150);
        if(dut.brightness_current!=0)begin $display("FAIL single-key dark");$finish;end
        short_key(0);wait_frames(150);
        if(dut.brightness_current!=127)begin $display("FAIL single-key wrap");$finish;end
        keys[0]=0;wait_frames(350);
        prior_gain=dut.master_gain;prior_bend=dut.bend_ratio;
        for(n=0;n<8;n=n+1)short_key(0);wait_frames(300);
        if(dut.brightness_current!=0 || dut.master_gain!=prior_gain || dut.bend_ratio!=prior_bend || dut.voice_count!=1)
            begin $display("FAIL independent modal brightness");$finish;end
        short_key(1);wait_frames(10);keys[4]=0;wait_frames(300);
        if(!dut.selected_guitar || dut.brightness_current!=0 || dut.monitor_guitar_keys!==13'h10 || dut.monitor_piano_keys!==13'h1)
            begin $display("FAIL KEY2 mode or mixed-note ownership");$finish;end
        set_knob(64,127);
        if(dut.brightness_current!=0 || dut.master_gain>=prior_gain || dut.bend_ratio<=prior_bend)
            begin $display("FAIL independent modal knobs");$finish;end
        bk[0]=0;repeat(50200)@(negedge clk);bk[0]=1;wait_frames(150);
        if(dut.brightness_current!=127 || !dut.selected_guitar)begin $display("FAIL long restore/mode");$finish;end
        keys=0;send("HELLO\n");send("NOTE_ON 73 100 0\n");send("NOTE_ON 74 100 0\n");send("NOTE_ON 75 100 0\n");wait_frames(150);
        if(dut.voice_count!=16)begin $display("FAIL modal full16");$finish;end
        for(n=0;n<8;n=n+1)short_key(0);wait_frames(150);
        set_knob(0,64);wait_frames(400);
        if(dut.output_sample_data!==0)begin $display("FAIL modal muted output");$finish;end
        set_knob(127,64);wait_frames(50);
        keys=13'h1fff;send("NOTE_OFF 73 0\n");send("NOTE_OFF 74 0\n");send("NOTE_OFF 75 0\n");wait_frames(7000);
        if(dut.voice_count!=0 || dut.tone_tail || pa!==1 || left_word!=0 || right_word!=0)
            begin $display("FAIL modal finite tail/silence");$finish;end
        if(nonzero<1000)begin $display("FAIL modal vacuous audio");$finish;end
        $fclose(fd);
        $display("PASS tb_expression_modal: KEY1 tone/KEY2 mode, mixed presets, full16, R927, %0d serial words, no underrun, finite tails",words);$finish;
    end
    initial begin #300000000;$display("FAIL modal expression timeout");$finish;end
endmodule
