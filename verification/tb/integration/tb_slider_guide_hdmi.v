`timescale 1ns/1ps
// 正式HDMI入口：真实三路I2C->明亮度；导奏只观察事件。
// 独立无显示核心接收相同输入，逐拍比较DAC/PA/PC回包，证明显示不反压发声。
module tb_slider_guide_hdmi;
    reg clk=0,rst_n=0,hpd=1,rx=1;
    reg [1:0] bk=3;
    reg [12:0] keys=13'h1fff;
    tri1 sda;
    wire scl;
    wire [4:0] audio,reference_audio;
    GSR GSR(.GSRI(1'b1));
    always #10 clk=~clk;
    piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .DISPLAY_LOCK_CYCLES(8),.UART_CLKS_PER_BIT(16),.BLE_CLKS_PER_BIT(40)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.uart_tx(audio[4]),
        .hdmi_hpd(hpd),.HP_BCK(audio[3]),.HP_WS(audio[2]),.HP_DIN(audio[1]),.PA_EN(audio[0]),
        .knob_sda(sda),.knob_scl(scl),.tmds_data_p(),.tmds_data_n(),.tmds_clk_p(),.tmds_clk_n(),
        .ble_rx(1'b1),.ble_tx(),.ble_state(1'b0));
    slider_adc_model adc(.scl(scl),.sda(sda));
    instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .UART_CLKS_PER_BIT(16),.BLE_CLKS_PER_BIT(40),.ENABLE_BLE(1),.FIXED_PIANO(1),
        .EXTERNAL_PIANO_KEYS(1),.VOICES(16),.ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),
        .ENABLE_OCTAVE_KEY(1),.USE_MODAL(1),.REQUEST_LEAD_HALF_EDGES(60),
        .ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),.ENABLE_CHORUS(1),.ENABLE_DELAY(1),.ENABLE_REVERB(1)) reference(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.uart_tx(reference_audio[4]),
        .HP_BCK(reference_audio[3]),.HP_WS(reference_audio[2]),.HP_DIN(reference_audio[1]),.PA_EN(reference_audio[0]),
        .ble_rx(1'b1),.ble_tx(),.ble_state(1'b0),.knob_value_flat(dut.knob_value_flat),
        .knob_valid(dut.knob_valid),.param_ready(dut.param_ready),.param_fault(dut.param_fault),
        .control_sustain(1'b0),.control_octave(2'd1),.control_brightness(dut.brightness_target),
        .control_ready(),.monitor_audio_valid(),.monitor_audio_sample(),.monitor_key_down(),
        .monitor_instrument_guitar(),.monitor_piano_keys(),.monitor_guitar_keys(),.monitor_octave(),
        .monitor_brightness(),.monitor_note_on(),.monitor_event_note());
    integer cycle=0,issue=0,samples=0,changed=0,since_reset=0;
    reg signed [15:0] captured_raw;
    reg [6:0] captured_brightness;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!dut.core_ready)since_reset=0;
        if(dut.core_ready)begin
            if(dut.u_core.sample_request)begin issue=cycle;since_reset=since_reset+1;end
            if(dut.u_core.sample_valid)begin captured_raw=dut.u_core.sample_data;captured_brightness=dut.brightness_current;end
            if(dut.u_core.tone_sample_valid)begin
                if(captured_brightness==127 && dut.u_core.tone_sample_data!==captured_raw)begin $display("FAIL slider neutral PCM");$stop;end
                if(captured_brightness<127 && dut.u_core.tone_sample_data!=captured_raw)changed=changed+1;
            end
            if(dut.u_core.output_sample_valid)begin
                if(cycle-issue!=953)begin $display("FAIL slider guide R953");$stop;end
                samples=samples+1;
            end
            if(since_reset>4 && dut.u_core.sample_underrun)begin $display("FAIL slider guide audio underrun");$stop;end
        end
        #1;if(rst_n && audio!==reference_audio)begin $display("FAIL guide/HDMI changed audio or UART at cycle %0d",cycle);$stop;end
    end
    task key;
        input integer index;
        begin @(negedge clk);keys[index]=0;repeat(70)@(negedge clk);keys[index]=1;repeat(70)@(negedge clk);end
    endtask
    task frames;
        input integer count;
        integer started;
        begin started=samples;wait(samples>=started+count);@(negedge clk);end
    endtask
    task bright;
        input [15:0] raw;
        input [6:0] expected;
        time started;
        begin
            started=$time;adc.input2=raw;
            while(dut.brightness_current!==expected)begin
                @(negedge clk);
                if($time-started>10000000)begin $display("FAIL slider top response");$stop;end
            end
            if(dut.u_core.master_gain!=65536 || dut.u_core.bend_ratio!=65536)begin $display("FAIL slider changed other controls");$stop;end
        end
    endtask
    initial begin
        repeat(10)@(negedge clk);rst_n=1;wait(dut.slider_ready && dut.param_ready);frames(2);
        if(dut.guide_progress!=1 || !dut.guide_valid || dut.guide_index!=0)begin $display("FAIL guide top start");$stop;end
        key(2);if(dut.guide_progress!=1)begin $display("FAIL guide wrong key");$stop;end
        keys[0]=0;frames(6);
        if(dut.guide_progress!=2)begin $display("FAIL guide held key advanced");$stop;end
        keys[0]=1;frames(2);key(0);frames(2);
        if(dut.guide_progress!=3 || dut.guide_index!=7)begin $display("FAIL guide repeated note");$stop;end
        key(7);frames(2);
        bk[1]=0;repeat(70)@(negedge clk);bk[1]=1;frames(2);
        if(dut.guide_progress!=4 || !dut.instrument_guitar)begin $display("FAIL guide instrument changed progress");$stop;end
        bk[0]=0;repeat(70)@(negedge clk);bk[0]=1;frames(2);
        if(dut.guide_progress!=4 || dut.current_octave!=2)begin $display("FAIL guide octave reset progress");$stop;end
        key(7);frames(2);
        if(dut.guide_progress!=5 || dut.guide_index!=9)begin $display("FAIL guide high guitar accepted note");$stop;end
        keys[9]=0;frames(150);bright(0,0);frames(80);bright(26400,127);
        hpd=0;frames(5);hpd=1;frames(5);
        if(dut.guide_progress!=6 || changed<20)begin $display("FAIL guide/sliding/filter coverage");$stop;end
        adc.connected=0;wait(dut.param_fault);frames(150);
        if(dut.brightness_target!=127)begin $display("FAIL slider top fault fallback");$stop;end
        adc.input2=13200;adc.connected=1;wait(dut.slider_ready && !dut.param_fault);bright(13200,64);
        rst_n=0;keys=13'h1fff;repeat(10)@(negedge clk);rst_n=1;wait(dut.core_ready);frames(3);
        if(dut.guide_progress!=1 || dut.guide_index!=0 || dut.current_octave!=1 || dut.instrument_guitar)begin $display("FAIL guide dirty reset");$stop;end
        $display("PASS tb_slider_guide_hdmi: actual I2C/slider/filter; correct/wrong/held/repeated keys; guitar/octave; HDMI loss/reset; exact DAC/PA/UART audio isolation samples=%0d",samples);$finish;
    end
    initial begin #100000000;$display("FAIL slider guide top timeout");$stop;end
endmodule
