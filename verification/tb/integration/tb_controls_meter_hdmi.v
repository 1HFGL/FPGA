`timescale 1ns/1ps
// Current guide-free HDMI top against the same audio core, with real timed I2C.
module tb_controls_meter_hdmi;
    parameter integer VOICES=32;
    reg clk=0,rst_n=0,hpd=1;
    reg [12:0] keys=13'h1fff;
    reg rx=1;
    tri1 sda;
    wire scl;
    wire [4:0] audio,reference_audio;
    GSR GSR(.GSRI(1'b1));
    always #10 clk=~clk;
    piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .DISPLAY_LOCK_CYCLES(8),.VOICES(VOICES),.UART_CLKS_PER_BIT(16)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(keys),
        .uart_rx(rx),.uart_tx(audio[4]),.hdmi_hpd(hpd),
        .HP_BCK(audio[3]),.HP_WS(audio[2]),.HP_DIN(audio[1]),.PA_EN(audio[0]),
        .knob_sda(sda),.knob_scl(scl),.ble_rx(1'b1),.ble_state(1'b0));
    slider_adc_model adc(.scl(scl),.sda(sda));
    instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .ENABLE_BLE(1),.FIXED_PIANO(1),.EXTERNAL_PIANO_KEYS(1),.VOICES(VOICES),.UART_CLKS_PER_BIT(16),
        .ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),.ENABLE_OCTAVE_KEY(1),.USE_MODAL(1),
        .REQUEST_LEAD_HALF_EDGES(60),.ENABLE_BRIGHTNESS(1),.EXTERNAL_BRIGHTNESS(1),
        .ENABLE_CHORUS(1),.ENABLE_DELAY(1),.ENABLE_REVERB(1)) reference(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(keys),
        .uart_rx(rx),.uart_tx(reference_audio[4]),.HP_BCK(reference_audio[3]),
        .HP_WS(reference_audio[2]),.HP_DIN(reference_audio[1]),.PA_EN(reference_audio[0]),
        .ble_rx(1'b1),.ble_state(1'b0),.knob_value_flat(dut.knob_value_flat),
        .knob_valid(dut.knob_valid),.param_ready(dut.param_ready),.param_fault(dut.param_fault),
        .control_sustain(1'b0),.control_octave(2'd1),.control_brightness(dut.brightness_target));
    integer cycle=0,issue=0,samples=0,nonzero=0,frames_since_reset=0;
    integer i,heard[0:31];
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!dut.core_ready)frames_since_reset=0;
        else begin
            if(dut.u_core.sample_request)begin issue=cycle;frames_since_reset=frames_since_reset+1;end
            if(dut.u_core.output_sample_valid)begin
                if(cycle-issue!=955)begin $display("FAIL current R955");$finish;end
                samples=samples+1;
                if(dut.u_core.output_sample_data!=0)nonzero=nonzero+1;
                for(i=0;i<32;i=i+1)if(dut.u_core.g_modal.u_bank.u_modal.last_voice[i]!=0)heard[i]=heard[i]+1;
            end
            if(frames_since_reset>4 && dut.u_core.sample_underrun)begin $display("FAIL current underrun");$finish;end
        end
        #1;if(rst_n && audio!==reference_audio)begin $display("FAIL current HDMI audio isolation");$finish;end
    end
    task frames;
        input integer count;
        integer begun;
        begin begun=samples;wait(samples>=begun+count);@(negedge clk);end
    endtask
    task send;
        input [511:0] message;
        integer length,a,b,j;
        begin
            length=0;for(j=0;j<64;j=j+1)if(message[j*8+:8]!=0)length=j+1;
            for(a=length-1;a>=0;a=a-1)begin
                @(negedge clk);rx=0;repeat(16)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=message[a*8+b];repeat(16)@(negedge clk);end
                rx=1;repeat(16)@(negedge clk);
            end
            repeat(80)@(negedge clk);
        end
    endtask
    initial begin
        for(i=0;i<32;i=i+1)heard[i]=0;
        repeat(8)@(negedge clk);rst_n=1;
        wait(dut.param_ready && dut.slider_ready);frames(4);
        if(dut.ENABLE_GUIDE!=0 || dut.guide_valid || dut.guide_progress!=0 ||
           dut.u_display.BRIGHTNESS_PANEL!=1 || dut.u_adc.HYSTERESIS_COUNTS!=384)begin
            $display("FAIL formal feature configuration");$finish;
        end
        keys=~13'h091;frames(64);
        if(dut.held_keys!==13'h091 || nonzero<8)begin $display("FAIL first chord/audio");$finish;end
        keys=0;send("HELLO\n");
        send("NOTE_ON 73 100 0\n");send("NOTE_ON 74 100 0\n");send("NOTE_ON 75 100 0\n");
        send("NOTE_ON 76 100 0\n");send("NOTE_ON 77 100 0\n");send("NOTE_ON 78 100 0\n");
        send("NOTE_ON 79 100 0\n");send("NOTE_ON 80 100 0\n");send("NOTE_ON 81 100 0\n");
        send("NOTE_ON 82 100 0\n");send("NOTE_ON 83 100 0\n");send("NOTE_ON 84 100 0\n");
        send("NOTE_ON 85 100 0\n");send("NOTE_ON 86 100 0\n");send("NOTE_ON 87 100 0\n");
        send("NOTE_ON 88 100 0\n");send("NOTE_ON 89 100 0\n");send("NOTE_ON 90 100 0\n");
        send("NOTE_ON 91 100 0\n");frames(64);
        if(dut.u_core.voice_count!=32 || dut.u_core.steal_count!=0 || dut.held_keys!==13'h1fff)begin
            $display("FAIL merged full32 voices=%0d steals=%0d held=%h",dut.u_core.voice_count,dut.u_core.steal_count,dut.held_keys);$finish;
        end
        for(i=0;i<32;i=i+1)if(heard[i]<4)begin $display("FAIL merged voice silent %0d",i);$finish;end
        send("NOTE_ON 92 100 0\n");frames(2);
        if(dut.u_core.voice_count!=32 || dut.u_core.steal_count!=1)begin $display("FAIL merged 33rd steal");$finish;end
        hpd=0;frames(4);hpd=1;frames(4);
        keys=13'h1fff;send("PANIC\n");frames(8);
        if(dut.held_keys!==0)begin $display("FAIL current key release");$finish;end
        rst_n=0;repeat(8)@(negedge clk);rst_n=1;frames(8);
        if(dut.guide_valid || dut.guide_progress!=0 || dut.held_keys!=0)begin $display("FAIL current reset");$finish;end
        $display("PASS tb_controls_meter_hdmi: actual ADC/filter, brightness/no-guide, 13 keys+19 UART=32 audible voices, 33rd steal, release, exact DAC/PA/UART isolation, R955, HPD/reset samples=%0d",samples);$finish;
    end
    initial begin #20000000;$display("FAIL current top timeout");$finish;end
endmodule
