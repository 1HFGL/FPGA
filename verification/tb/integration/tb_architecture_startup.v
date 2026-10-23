`timescale 1ns/1ps
module tb_architecture_startup;
    reg clk=0,rst_n=0;
    reg [1:0] board_keys=2'b11;
    reg [12:0] keys=13'h1fff;
    reg rx=1,hpd=0;
    tri1 sda,sda_ref;
    wire scl,scl_ref,pa,pa_ref;
    wire [2:0] audio,audio_ref;
    GSR GSR(.GSRI(1'b1));
    always #10 clk=~clk;
    piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DISPLAY_LOCK_CYCLES(4),
        .DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(board_keys),.piano_key_n(keys),
        .uart_rx(rx),.hdmi_hpd(hpd),.uart_tx(),.HP_BCK(audio[2]),.HP_WS(audio[1]),.HP_DIN(audio[0]),.PA_EN(pa),
        .knob_sda(sda),.knob_scl(scl),.tmds_data_p(),.tmds_data_n(),.tmds_clk_p(),.tmds_clk_n());
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .UART_CLKS_PER_BIT(16)) baseline(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(board_keys),.piano_key_n(keys),
        .uart_rx(rx),.uart_tx(),.HP_BCK(audio_ref[2]),.HP_WS(audio_ref[1]),.HP_DIN(audio_ref[0]),.PA_EN(pa_ref),
        .knob_sda(sda_ref),.knob_scl(scl_ref));
    integer samples=0,nonzero=0,drops=0,v;
    reg [15:0] heard=0;
    always @(posedge clk)begin
        #1;
        if(rst_n && dut.core_ready && baseline.core_ready)begin
            if({audio,pa,dut.audio_valid,dut.audio_sample}!==
               {audio_ref,pa_ref,baseline.u_core.monitor_audio_valid,baseline.u_core.monitor_audio_sample})begin
                $display("FAIL formal HDMI audio isolation samples=%0d",samples);$finish;
            end
            // 帧发送器启动时缓存尚未填充；沿用既有四帧启动资格，之后逐拍检查截止期。
            if(samples>4 && (dut.u_core.sample_underrun || dut.u_core.g_modal.core_overrun))begin
                $display("FAIL formal HDMI audio deadline");$finish;
            end
            if(dut.audio_valid)begin
                samples=samples+1;if(dut.audio_sample!=0)nonzero=nonzero+1;
                for(v=0;v<16;v=v+1)if(dut.u_core.g_modal.u_bank.u_modal.last_voice[v]!=0)heard[v]=1;
            end
            if(dut.u_display.display_sample_drop)drops=drops+1;
        end
    end
    task frames;
        input integer count;
        integer first;
        begin first=samples;wait(samples>=first+count);@(negedge clk);end
    endtask
    task send;
        input [511:0] text;
        integer index,bit_index;
        reg [7:0] byte_value;
        begin
            for(index=63;index>=0;index=index-1)begin
                byte_value=text[index*8+:8];
                if(byte_value!=0)begin
                    @(negedge clk);rx=0;repeat(16)@(negedge clk);
                    for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
                        rx=byte_value[bit_index];repeat(16)@(negedge clk);
                    end
                    rx=1;repeat(16)@(negedge clk);
                end
            end
            repeat(40)@(negedge clk);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);
        if(dut.volume!==127 || dut.bend!==0 || dut.u_core.g_controls.u_parameters.master_gain!==65536)
            begin $display("FAIL startup volume disagrees with audio");$finish;end
        rst_n=1;wait(dut.core_ready);repeat(20)@(negedge clk);
        if(dut.volume!==127)begin $display("FAIL startup volume changed without ADC");$finish;end
        force dut.knob_value_flat={7'd64,7'd23};
        force baseline.knob_value_flat={7'd64,7'd23};
        force dut.knob_valid=1'b1;force dut.param_ready=1'b1;force dut.param_fault=1'b1;
        force baseline.knob_valid=1'b1;force baseline.param_ready=1'b1;force baseline.param_fault=1'b1;
        repeat(3)@(negedge clk);
        if(dut.volume!==127)begin $display("FAIL fault updated volume");$finish;end
        force dut.param_fault=1'b0;force baseline.param_fault=1'b0;repeat(3)@(negedge clk);
        if(dut.volume!==23 || dut.bend!==0)begin $display("FAIL accepted ADC display");$finish;end
        force dut.knob_value_flat={7'd64,7'd127};force baseline.knob_value_flat={7'd64,7'd127};
        hpd=1;wait(dut.display_reset);keys=0;frames(100);
        send("HELLO\n");send("NOTE_ON 84 100 0\n");send("NOTE_ON 85 100 0\n");send("NOTE_ON 86 100 0\n");frames(80);
        if(dut.u_core.voice_count!=16 || heard!==16'hffff)begin
            $display("FAIL formal HDMI full16 count=%0d heard=%h",dut.u_core.voice_count,heard);$finish;
        end
        hpd=0;#1;
        if(dut.display_reset)begin $display("FAIL formal HDMI unplug reset");$finish;end
        frames(16);hpd=1;wait(dut.display_reset);frames(16);
        force dut.pll_locked=1'b0;frames(16);release dut.pll_locked;
        wait(dut.display_reset);frames(16);
        force dut.pixel_clk=1'b0;frames(16);release dut.pixel_clk;frames(16);
        if(drops<10)begin $display("FAIL formal stopped pixel not exercised");$finish;end
        board_keys[1]=0;frames(4);board_keys[1]=1;
        keys[12]=1;frames(4);keys[12]=0;frames(80);
        if(!dut.instrument_guitar || dut.guitar_held_keys[12]!==1'b1)begin
            $display("FAIL formal HDMI mode after recovery");$finish;
        end
        if(nonzero<200)begin $display("FAIL formal HDMI ineffective audio");$finish;end
        rst_n=0;repeat(20)@(negedge clk);
        if(dut.volume!==127)begin $display("FAIL startup volume reset recovery");$finish;end
        $display("PASS tb_architecture_startup: startup127/no-ADC/fault/accepted pair/reset; full16/HPD/PLL/pixel-stop/mode; %0d identical formal audio samples, %0d drops",samples,drops);$finish;
    end
    initial begin #20000000;$display("FAIL startup timeout");$finish;end
endmodule
