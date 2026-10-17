`timescale 1ns/1ps
// 与无显示的正式顶层逐拍比较真实串行音频；拔屏/失锁不得打断声音。
module tb_hdmi_audio_isolation;
    reg clk=0,rst=0,hpd=1;
    reg [1:0] board_keys=3;
    reg [12:0] keys=13'h1fff;
    reg [13:0] knobs={7'd64,7'd127};
    reg valid=0,fault=0;
    wire [4:0] audio_hdmi,audio_base;
    tri1 sda_hdmi,sda_base;
    wire scl_hdmi,scl_base;
    wire [2:0] dp,dn;wire cp,cn;
    always #10 clk=~clk;
    GSR GSR(.GSRI(1'b1));
    piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),.DISPLAY_LOCK_CYCLES(8)) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(board_keys),.piano_key_n(keys),.uart_rx(1'b1),.hdmi_hpd(hpd),
        .uart_tx(audio_hdmi[4]),.HP_BCK(audio_hdmi[3]),.HP_WS(audio_hdmi[2]),.HP_DIN(audio_hdmi[1]),.PA_EN(audio_hdmi[0]),
        .knob_sda(sda_hdmi),.knob_scl(scl_hdmi),.tmds_data_p(dp),.tmds_data_n(dn),.tmds_clk_p(cp),.tmds_clk_n(cn));
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8)) baseline(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(board_keys),.piano_key_n(keys),.uart_rx(1'b1),
        .uart_tx(audio_base[4]),.HP_BCK(audio_base[3]),.HP_WS(audio_base[2]),.HP_DIN(audio_base[1]),.PA_EN(audio_base[0]),
        .knob_sda(sda_base),.knob_scl(scl_base));
    integer samples=0,nonzero=0,cycles=0,k,since_reset=0;
    always @(posedge clk)begin
        #1;
        if(!rst)since_reset=0;
        if(rst)begin
            cycles=cycles+1;
            if(audio_hdmi!==audio_base)begin $display("FAIL HDMI changed audio output cycle=%0d",cycles);$finish;end
            if(dut.audio_valid)begin
                samples=samples+1;since_reset=since_reset+1;if(dut.audio_sample!=0)nonzero=nonzero+1;
            end
            // 原基线启动首帧无待发样本，双方都发送零；运行期任何新增欠载都失败。
            if(dut.u_core.sample_underrun!==baseline.u_core.sample_underrun ||
                (since_reset>4 && dut.u_core.sample_underrun))begin $display("FAIL HDMI audio underrun");$finish;end
        end
    end
    task knob;
        input [6:0] volume,bend;
        begin
            @(negedge clk);knobs={bend,volume};valid=1;
            @(negedge clk);valid=0;
        end
    endtask
    initial begin
        // 注入C->B已接受采样接口，ADC总线另由已有ADC联合仿真覆盖，不改队友tb。
        force dut.knob_value_flat=knobs;force baseline.knob_value_flat=knobs;
        force dut.knob_valid=valid;force baseline.knob_valid=valid;
        force dut.param_ready=1'b1;force baseline.param_ready=1'b1;
        force dut.param_fault=fault;force baseline.param_fault=fault;
        #105;rst=1;wait(dut.core_ready);wait(dut.display_reset);
        if(dut.volume!==127 || dut.bend!==0)begin $display("FAIL display defaults");$finish;end
        @(negedge clk);keys[0]=0;
        repeat(100)@(negedge clk);
        if(dut.held_keys!==13'b1)begin $display("FAIL accepted note highlight");$finish;end
        board_keys[1]=0;repeat(40)@(negedge clk);
        if(dut.instrument_guitar!==1 || dut.u_display.instrument_guitar!==1 ||
           baseline.u_core.monitor_instrument_guitar!==1 || dut.u_core.voice_count!=1)begin
            $display("FAIL HDMI actual mode/key isolation");$finish;
        end
        board_keys[1]=1;keys[4]=0;repeat(2000)@(negedge clk);
        if(dut.u_core.voice_count!=2 || dut.u_core.u_bank.g_voice[1].u_voice.g_dual.u_instrument.active_instrument!==0)begin
            $display("FAIL HDMI guitar audio not integrated");$finish;
        end
        knob(32,0);
        if(dut.volume!==32 || dut.bend!==-16'sd32768)begin $display("FAIL low knob display");$finish;end
        knob(127,127);
        if(dut.volume!==127 || dut.bend!==32767)begin $display("FAIL high knob display");$finish;end
        knob(96,63);
        if(dut.bend!==0)begin $display("FAIL center 63");$finish;end
        knob(96,64);
        if(dut.bend!==0)begin $display("FAIL center 64");$finish;end
        fault=1;knob(0,0);
        if(dut.volume!==96 || dut.bend!==0)begin $display("FAIL bad ADC altered display");$finish;end
        fault=0;
        // 稳定发声时拔屏、重插、再模拟PLL失锁；音频输出必须仍与无显示版完全一致。
        repeat(60000)@(negedge clk);hpd=0;
        #1;if(dut.display_reset!==0)begin $display("FAIL HPD reset");$finish;end
        repeat(10000)@(negedge clk);hpd=1;
        wait(dut.display_reset);force dut.pll_locked=1'b0;
        repeat(10000)@(negedge clk);release dut.pll_locked;
        wait(dut.display_reset);
        @(negedge clk);keys[0]=1;keys[4]=1;
        repeat(100)@(negedge clk);
        if(dut.held_keys!==0)begin $display("FAIL released key still highlighted");$finish;end
        if(samples<70 || nonzero<20)begin $display("FAIL insufficient audible samples");$finish;end
        rst=0;#100;rst=1;wait(dut.core_ready);repeat(10)@(negedge clk);
        if(dut.held_keys!==0 || dut.volume!==127 || dut.bend!==0 || dut.instrument_guitar!==0)begin $display("FAIL integrated reset defaults");$finish;end
        $display("PASS tb_hdmi_audio_isolation: serial audio identical, actual key/knob/wave taps, unplug/unlock/reset (%0d samples)",samples);$finish;
    end
    initial begin #5000000;$display("FAIL isolation timeout");$finish;end
endmodule
