`timescale 1ns/1ps
// Full audio path at 50MHz/48kHz; shorten only key repeat/debounce and note release.
module tb_performance_brightness;
    reg clk=0,rst_n=0,rx=1,kv=0;
    reg [1:0] board_keys=3;
    reg [12:0] keys=13'h1fff;
    reg [13:0] knobs={7'd64,7'd127};
    wire bck,ws,din,pa;
    integer frames=0,segment=0,fd,bits=0,words=0,k,vc,frame_words=0;
    reg [15:0] word=0,left_word=0,right_word=0,expected_word=0;
    reg [15:0] expected_pcm[0:10000];
    integer pcm_written=0,pcm_read=0;
    reg [31:0] expected_inc;
    reg [16:0] original_gain;
    reg [17:0] original_bend;
    instrument_uart_top #(.VOICES(16),.ENABLE_CONTROLS(1),.ENABLE_BRIGHTNESS(1),
        .EXTERNAL_PIANO_KEYS(1),.BRIGHTNESS_REPEAT_CYCLES(5000),.DEBOUNCE_CYCLES(8),
        .UART_CLKS_PER_BIT(16),.WATCHDOG_CYCLES(150000000),.ROM_FILE("rtl/rom/piano_1024.mem"),
        .ATTACK_SAMPLES(4),.DECAY_SAMPLES(4),.SUSTAIN_LEVEL(65536),.RELEASE_SAMPLES(64),
        .REQUEST_LEAD_HALF_EDGES(2)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(board_keys),.piano_key_n(keys),.uart_rx(rx),.uart_tx(),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_value_flat(knobs),.knob_valid(kv),
        .param_ready(1'b1),.param_fault(1'b0),.control_sustain(1'b0),.control_octave(2'd1),.control_ready());
    always #10 clk=~clk;
    always @(posedge clk)begin
        if(dut.audio_ready && dut.sample_request)frames=frames+1;
        if(dut.audio_ready && frames>5 && (dut.sample_underrun || dut.tone_overrun))begin $display("FAIL sample deadline");$finish;end
        if(dut.output_sample_valid)begin
            $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d\n",frames,segment,$signed(dut.sample_data),
                dut.brightness_current,$signed(dut.output_sample_data),dut.master_gain);
            expected_pcm[pcm_written]=dut.output_sample_data;pcm_written=pcm_written+1;
        end
        // Shadow the public frame boundary, then decode the actual DAC pins.
        if(dut.audio_ready && dut.output_frame_start)begin
            if(pcm_read<pcm_written)begin expected_word=expected_pcm[pcm_written-1];pcm_read=pcm_written;end
            else expected_word=0;
        end
        #1;
        if(dut.audio_ready && pa && (right_word!=0 || left_word!=0))begin $display("FAIL PA truncated tail");$finish;end
    end
    always @(posedge bck)if(dut.audio_ready)begin
        word={word[14:0],din};bits=bits+1;
        if(bits==16)begin
            bits=0;words=words+1;
            if(ws)left_word=word;else right_word=word;
            if(word!==expected_word)begin $display("FAIL DAC word got=%0d expected=%0d",$signed(word),$signed(expected_word));$finish;end
        end
    end
    task wait_frames;input integer count;integer start;
        begin start=frames;wait(frames>=start+count);@(negedge clk);end
    endtask
    task set_knobs;input [6:0] volume,bend;
        begin knobs={bend,volume};kv=1;@(negedge clk);kv=0;wait_frames(150);end
    endtask
    task send;input [511:0] text;integer bytes,a,b,j;
        begin
            bytes=0;for(j=0;j<64;j=j+1)if(text[j*8+:8]!=0)bytes=j+1;
            for(a=bytes-1;a>=0;a=a-1)begin
                @(negedge clk);rx=0;repeat(16)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
                rx=1;repeat(16)@(negedge clk);
            end
            repeat(40)@(negedge clk);
        end
    endtask
    initial begin
        fd=$fopen("build/expression/performance_brightness.csv","w");
        $fwrite(fd,"frame,segment,raw,brightness,filtered,gain\n");
        repeat(8)@(negedge clk);rst_n=1;wait_frames(8);
        // Board buttons are expression only, and must not create alias notes.
        board_keys=2;wait_frames(190);board_keys=3;wait_frames(180);
        if(dut.voice_count!=0 || dut.brightness_current!=0 || pa!==1)begin $display("FAIL idle expression/aliases");$finish;end
        board_keys=0;wait_frames(160);board_keys=3;wait_frames(15);
        if(dut.brightness_current!=127)begin $display("FAIL restore");$finish;end
        keys[0]=0;wait_frames(40);segment=1;wait_frames(1200);segment=0;
        original_gain=dut.master_gain;original_bend=dut.bend_ratio;
        board_keys=2;wait_frames(200);board_keys=3;wait_frames(200);
        if(dut.brightness_current!=0 || dut.master_gain!=original_gain || dut.bend_ratio!=original_bend || dut.voice_count!=1)
            begin $display("FAIL independent brightness");$finish;end
        segment=2;wait_frames(1200);segment=0;
        set_knobs(64,64);segment=3;wait_frames(1200);segment=0;
        if(dut.brightness_current!=0 || dut.bend_ratio!=original_bend || dut.master_gain>=original_gain)
            begin $display("FAIL independent volume");$finish;end
        set_knobs(64,127);segment=4;wait_frames(1200);segment=0;
        if(dut.brightness_current!=0 || dut.bend_ratio<=original_bend)begin $display("FAIL independent bend");$finish;end
        // All physical keys plus three UART notes still share sixteen voices.
        keys=0;send("HELLO\n");send("NOTE_ON 73 100 0\n");send("NOTE_ON 74 100 0\n");send("NOTE_ON 75 100 0\n");wait_frames(150);
        if(dut.voice_count!=16)begin $display("FAIL full16 %0d",dut.voice_count);$finish;end
        set_knobs(0,64);wait_frames(400);
        if(dut.output_sample_data!==0)begin $display("FAIL filtered mute");$finish;end
        set_knobs(127,64);wait_frames(50);
        keys=13'h1fff;send("NOTE_OFF 73 0\n");send("NOTE_OFF 74 0\n");send("NOTE_OFF 75 0\n");
        wait_frames(600);
        if(dut.voice_count!=0 || dut.tone_tail || pa!==1 || left_word!=0 || right_word!=0)
            begin $display("FAIL final silence");$finish;end
        $fclose(fd);
        $display("PASS tb_performance_brightness: independent tone/volume/bend, 13+3 voices, %0d serial words, finite tails, no underrun",words);$finish;
    end
    initial begin #300000000;$display("FAIL brightness integration timeout");$finish;end
endmodule
