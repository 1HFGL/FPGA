`timescale 1ns/1ps
// 正式有屏/无屏两个顶层，共同驱动13键和UART至16声部，逐拍比较真实音频引脚。
module tb_final_hdmi_isolation;
    reg clk=0,rst=0,hpd=1,rx=1;
    reg [1:0] bk=3;
    reg [12:0] keys=13'h1fff;
    reg [13:0] knobs={7'd64,7'd127};
    reg kv=0,fault=0;
    tri1 sda1,sda2;
    wire scl1,scl2;
    wire [4:0] audio1,audio2;
    wire [2:0] dp,dn;wire cp,cn;
    GSR GSR(.GSRI(1'b1));
    always #10 clk=~clk;
    piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .DISPLAY_LOCK_CYCLES(8),.UART_CLKS_PER_BIT(16)) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),.hdmi_hpd(hpd),
        .uart_tx(audio1[4]),.HP_BCK(audio1[3]),.HP_WS(audio1[2]),.HP_DIN(audio1[1]),.PA_EN(audio1[0]),
        .knob_sda(sda1),.knob_scl(scl1),.tmds_data_p(dp),.tmds_data_n(dn),.tmds_clk_p(cp),.tmds_clk_n(cn));
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),.UART_CLKS_PER_BIT(16)) baseline(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(bk),.piano_key_n(keys),.uart_rx(rx),
        .uart_tx(audio2[4]),.HP_BCK(audio2[3]),.HP_WS(audio2[2]),.HP_DIN(audio2[1]),.PA_EN(audio2[0]),
        .knob_sda(sda2),.knob_scl(scl2));
    integer samples=0,since_reset=0,nonzero=0,drops=0,cycle=0,heard[0:15],i;
    always @(posedge clk)begin
        #1;cycle=cycle+1;
        if(!rst)since_reset=0;
        else begin
            if(audio1!==audio2)begin $display("FAIL final HDMI altered audio pins cycle=%0d",cycle);$finish;end
            if(dut.audio_valid)begin
                samples=samples+1;since_reset=since_reset+1;if(dut.audio_sample!=0)nonzero=nonzero+1;
                for(i=0;i<16;i=i+1)if(dut.u_core.g_modal.u_bank.u_modal.last_voice[i]!=0)heard[i]=heard[i]+1;
            end
            if(since_reset>4 && (dut.u_core.sample_underrun || dut.u_core.g_modal.core_overrun))begin $display("FAIL final HDMI deadline");$finish;end
            if(dut.u_display.display_sample_drop)drops=drops+1;
        end
    end
    task frames;
        input integer count;integer n;
        begin n=samples;wait(samples>=n+count);@(negedge clk);end
    endtask
    task send;
        input [511:0] text;integer bytes,a,b,k;
        begin
            bytes=0;for(k=0;k<64;k=k+1)if(text[k*8+:8]!=0)bytes=k+1;
            for(a=bytes-1;a>=0;a=a-1)begin
                @(negedge clk);rx=0;repeat(16)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[a*8+b];repeat(16)@(negedge clk);end
                rx=1;repeat(16)@(negedge clk);
            end repeat(40)@(negedge clk);
        end
    endtask
    task knob;
        input [6:0] vol,bend;
        begin @(negedge clk);knobs={bend,vol};kv=1;@(negedge clk);kv=0;end
    endtask
    initial begin
        for(i=0;i<16;i=i+1)heard[i]=0;
        force dut.knob_value_flat=knobs;force baseline.knob_value_flat=knobs;
        force dut.knob_valid=kv;force baseline.knob_valid=kv;
        force dut.param_ready=1'b1;force baseline.param_ready=1'b1;
        force dut.param_fault=fault;force baseline.param_fault=fault;
        #105;rst=1;wait(dut.core_ready);wait(dut.display_reset);
        if(dut.volume!==8 || dut.bend!==0)begin $display("FAIL final display startup gain");$finish;end
        knob(127,64);keys=0;frames(80);
        send("HELLO\n");send("NOTE_ON 84 100 0\n");send("NOTE_ON 85 100 0\n");send("NOTE_ON 86 100 0\n");frames(30);
        if(dut.u_core.voice_count!=16)begin $display("FAIL final HDMI full16");$finish;end
        for(i=0;i<16;i=i+1)if(heard[i]<10)begin $display("FAIL final HDMI silent voice %0d",i);$finish;end
        hpd=0;#1;if(dut.display_reset)begin $display("FAIL final unplug reset");$finish;end
        frames(20);hpd=1;wait(dut.display_reset);
        force dut.pll_locked=1'b0;frames(20);release dut.pll_locked;wait(dut.display_reset);
        force dut.pixel_clk=1'b0;frames(20);release dut.pixel_clk;frames(20);
        if(drops<10)begin $display("FAIL final stopped pixel did not exercise mailbox");$finish;end
        bk[1]=0;frames(3);bk[1]=1;keys[12]=1;frames(2);keys[12]=0;frames(10);
        if(!dut.instrument_guitar || dut.guitar_held_keys!==13'h1000 || dut.piano_held_keys[12]!==0)begin
            $display("FAIL final mode/held feedback");$finish;end
        knob(32,0);frames(70);
        if(dut.volume!==32 || dut.bend!==-32768)begin $display("FAIL final accepted controls display");$finish;end
        fault=1;knob(0,127);frames(4);
        if(dut.volume!==32 || dut.bend!==-32768)begin $display("FAIL final bad ADC changed display");$finish;end
        fault=0;knob(127,64);frames(70);
        rst=0;keys=13'h1fff;#100;rst=1;frames(10);
        if(dut.volume!==8 || dut.instrument_guitar || dut.held_keys!==0)begin $display("FAIL final HDMI reset defaults");$finish;end
        if(nonzero<200)begin $display("FAIL final HDMI ineffective audible check");$finish;end
        $display("PASS tb_final_hdmi_isolation: full16 serial audio identical; mode/control, HPD/PLL/pixel-stop/reset, samples=%0d drops=%0d",samples,drops);$finish;
    end
    initial begin #20000000;$display("FAIL final HDMI isolation timeout");$finish;end
endmodule
