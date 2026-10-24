`timescale 1ns/1ps
// Current 32-voice formal HDMI top, real 48 kHz and real three-channel ADC timing.
// Observe the final DAC stream, not just the slider register or filter valid pulse.
module tb_brightness_hdmi;
    reg clk=0,rst_n=0,rx=1,hpd=1;
    reg [1:0] bk=3;
    reg [12:0] keys=13'h1fff;
    tri1 sda;
    wire scl;
    wire [4:0] audio,reference_audio;
    GSR GSR(.GSRI(1'b1));
    always #10 clk=~clk;
    piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .DISPLAY_LOCK_CYCLES(8),.UART_CLKS_PER_BIT(16)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),
        .uart_tx(audio[4]),.hdmi_hpd(hpd),.HP_BCK(audio[3]),.HP_WS(audio[2]),
        .HP_DIN(audio[1]),.PA_EN(audio[0]),.knob_sda(sda),.knob_scl(scl),
        .ble_rx(1'b1),.ble_state(1'b0));
    slider_adc_model adc(.scl(scl),.sda(sda));
    instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .UART_CLKS_PER_BIT(16),.ENABLE_BLE(1),.ENABLE_TOUCH(1),.FIXED_PIANO(1),
        .EXTERNAL_PIANO_KEYS(1),.VOICES(32),.ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),
        .ENABLE_OCTAVE_KEY(1),.USE_MODAL(1),.REQUEST_LEAD_HALF_EDGES(60),
        .ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),.ENHANCED_BRIGHTNESS(0),
        .ENABLE_CHORUS(1),.ENABLE_DELAY(1),.ENABLE_REVERB(1)) reference(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),
        .uart_tx(reference_audio[4]),.HP_BCK(reference_audio[3]),.HP_WS(reference_audio[2]),
        .HP_DIN(reference_audio[1]),.PA_EN(reference_audio[0]),
        .ble_rx(1'b1),.ble_state(1'b0),.knob_value_flat(dut.knob_value_flat),
        .knob_valid(dut.knob_valid),.param_ready(dut.param_ready),.param_fault(dut.param_fault),
        .control_sustain(1'b0),.control_octave(2'd1),.control_brightness(dut.brightness_target),
        .touch_event_valid(1'b0),.touch_cancel_valid(1'b0),.touch_event_on(1'b0),
        .touch_event_guitar(1'b0),.touch_event_source(8'd0),.touch_event_note(7'd0),.touch_event_velocity(7'd0));
    integer fd,cycle=0,issue=0,samples=0,since_reset=0,words=0,bits=0,phase=0,epoch=0;
    integer i,n,heard[0:31],full32=0,neutral=0,dark_changed=0;
    reg compare_original=1;
    reg [15:0] word=0,pending=0,active=0;
    reg pending_valid=0;
    reg signed [15:0] raw_sample,old_tone,new_tone,chorus_sample,delay_sample;
    reg [6:0] captured_brightness;
    always @(negedge rst_n)begin bits=0;word=0;end
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!dut.core_ready)begin since_reset=0;pending_valid=0;pending=0;active=0;end
        else begin
            if(dut.u_core.sample_request)begin issue=cycle;since_reset=since_reset+1;end
            if(dut.u_core.sample_valid)begin
                raw_sample=dut.u_core.sample_data;captured_brightness=dut.brightness_current;
                if(dut.u_core.sample_data!==reference.sample_data)begin $display("FAIL brightness altered synth");$finish;end
            end
            if(reference.tone_sample_valid)old_tone=reference.tone_sample_data;
            if(dut.u_core.tone_sample_valid)begin
                new_tone=dut.u_core.tone_sample_data;
                if(captured_brightness==127)begin
                    if(new_tone!==raw_sample)begin $display("FAIL brightness original tone");$finish;end
                    neutral=neutral+1;
                end
                if(captured_brightness==0 && new_tone!=old_tone)dark_changed=dark_changed+1;
            end
            if(dut.u_core.chorus_sample_valid)chorus_sample=dut.u_core.chorus_sample_data;
            if(dut.u_core.delay_sample_valid)delay_sample=dut.u_core.delay_sample_data;
            if(dut.u_core.output_frame_start)begin active<=pending_valid?pending:16'd0;pending_valid<=0;end
            if(dut.u_core.output_sample_valid)begin
                if(cycle-issue!=958)begin $display("FAIL brightness R958 got=%0d",cycle-issue);$finish;end
                pending<=dut.u_core.output_sample_data;pending_valid<=1;samples=samples+1;
                if(dut.u_core.voice_count==32)full32=full32+1;
                for(i=0;i<32;i=i+1)if(dut.u_core.g_modal.u_bank.u_modal.last_voice[i]!=0)heard[i]=heard[i]+1;
                $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",epoch,phase,captured_brightness,
                    $signed(raw_sample),$signed(old_tone),$signed(new_tone),$signed(chorus_sample),
                    $signed(delay_sample),$signed(dut.u_core.output_sample_data));
            end
            if(since_reset>4 && (dut.u_core.sample_underrun || dut.u_core.g_modal.core_overrun ||
                dut.u_core.tone_overrun || dut.u_core.chorus_overrun || dut.u_core.delay_overrun || dut.u_core.reverb_overrun))begin
                $display("FAIL brightness real-time deadline");$finish;end
            if(dut.u_core.master_gain!==reference.master_gain || dut.u_core.bend_ratio!==reference.bend_ratio)begin
                $display("FAIL brightness coupled volume/pitch");$finish;end
        end
        #1;if(rst_n && compare_original && audio!==reference_audio)begin $display("FAIL 127 DAC/PA/UART identity");$finish;end
    end
    always @(posedge audio[3])if(dut.core_ready)begin
        word={word[14:0],audio[1]};bits=bits+1;
        if(bits==16)begin
            bits=0;words=words+1;
            if(word!==active)begin $display("FAIL brightness DAC serial sample");$finish;end
        end
    end
    task frames;input integer count;integer start;
        begin start=samples;wait(samples>=start+count);@(negedge clk);end
    endtask
    task send;input [511:0] text;integer len,a,b,j;
        begin
            len=0;for(j=0;j<64;j=j+1)if(text[j*8+:8]!=0)len=j+1;
            for(a=len-1;a>=0;a=a-1)begin
                @(negedge clk);rx=0;repeat(16)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
                rx=1;repeat(16)@(negedge clk);
            end repeat(80)@(negedge clk);
        end
    endtask
    task note_on;input integer note;reg [7:0] tens,units;
        begin tens=48+note/10;units=48+note%10;send({"NOTE_ON ",tens,units," 100 0\n"});end
    endtask
    task slider;input [15:0] raw;input [6:0] value;time start;
        begin
            adc.input2=raw;start=$time;
            while(dut.brightness_current!==value)begin
                @(negedge clk);if($time-start>15000000)begin $display("FAIL brightness ADC response");$finish;end
            end
        end
    endtask
    initial begin
        for(i=0;i<32;i=i+1)heard[i]=0;
        fd=$fopen("build/brightness_response/hdmi.csv","w");
        if(!fd)begin $display("FAIL brightness capture file");$finish;end
        $fwrite(fd,"epoch,phase,brightness,raw,old,new,chorus,delay,output\n");
        adc.input0=3300;
        repeat(8)@(negedge clk);rst_n=1;wait(dut.param_ready && dut.slider_ready);frames(4);
        if(dut.VOICES!=32 || dut.ENHANCED_BRIGHTNESS!=1)begin $display("FAIL brightness formal config");$finish;end
        keys=0;send("HELLO\n");for(n=73;n<=91;n=n+1)note_on(n);frames(256);
        if(dut.u_core.voice_count!=32 || dut.u_core.steal_count!=0)begin $display("FAIL brightness 32 voices");$finish;end
        for(i=0;i<32;i=i+1)if(heard[i]<4)begin $display("FAIL brightness silent voice %0d",i);$finish;end
        compare_original=0;phase=1;slider(0,0);frames(512);
        phase=2;slider(13200,64);frames(512);
        phase=3;slider(26400,127);frames(256);
        note_on(92);frames(4);
        if(dut.u_core.steal_count!=1)begin $display("FAIL brightness 33rd steal");$finish;end
        keys=13'h1fff;send("PANIC\n");frames(4);
        rst_n=0;epoch=1;repeat(8)@(negedge clk);rst_n=1;
        wait(dut.param_ready && dut.slider_ready);frames(4);
        bk[1]=0;repeat(80)@(negedge clk);bk[1]=1;frames(8);
        if(!dut.instrument_guitar)begin $display("FAIL brightness guitar select");$finish;end
        phase=4;keys=~13'h091;frames(512);
        phase=5;slider(0,0);keys=13'h1fff;frames(8);keys=~13'h091;frames(512);
        phase=6;slider(13200,64);frames(512);
        phase=7;slider(26400,127);frames(256);
        hpd=0;frames(6);hpd=1;frames(6);
        adc.connected=0;wait(dut.param_fault);frames(150);
        if(dut.brightness_target!=127)begin $display("FAIL brightness fault fallback");$finish;end
        adc.connected=1;wait(dut.slider_ready && !dut.param_fault);frames(8);
        keys=13'h1fff;frames(128);rst_n=0;epoch=2;repeat(8)@(negedge clk);rst_n=1;frames(8);
        if(full32<512 || neutral<256 || dark_changed<256 || words<2000)begin $display("FAIL brightness coverage");$finish;end
        $fclose(fd);
        $display("PASS tb_brightness_hdmi: actual AIN2, 32 voices, both instruments, original 127 DAC exact, R958, serial=%0d samples=%0d full32=%0d dark=%0d",words,samples,full32,dark_changed);$finish;
    end
    initial begin #350000000;$display("FAIL brightness HDMI timeout");$finish;end
endmodule
