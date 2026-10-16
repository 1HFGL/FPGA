`timescale 1ns/1ps
// 真I2C位级->双通道ADC->旋钮->正式16声部顶层；仅加速转换等待/平滑。
module tb_performance_adc;
    reg clk=0,rst_n=0;
    reg [12:0] keys=13'h1ffe;
    tri1 sda;
    wire scl,tx,bck,ws,din,pa;
    integer frames=0;
    reg [16:0] held_gain;
    reg [17:0] held_ratio;
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8),
        .ADC_I2C_HZ(1000000),.ADC_CONV_WAIT(100),.ADC_READY_SAMPLES(1),
        .ADC_FILTER_SHIFT(0),.ADC_SLEW_STEP(127)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(keys),.uart_rx(1'b1),
        .uart_tx(tx),.HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.knob_sda(sda),.knob_scl(scl));
    performance_adc_model #(.CONV0(26400),.CONV1(13200)) adc(.sda(sda),.scl(scl));
    always #10 clk=~clk;
    always @(posedge clk)if(dut.u_core.audio_ready && dut.u_core.sample_request)frames=frames+1;
    task wait_frames;
        input integer count;
        integer f;
        begin f=frames;wait(frames>=f+count);@(negedge clk);end
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        wait(dut.param_ready && dut.knob_value_flat=={7'd64,7'd127});wait_frames(70);
        if(dut.u_core.master_gain!=65536 || dut.u_core.bend_ratio!=65536)begin $display("FAIL: ADC center/full scale");$finish;end
        adc.conversion0=0;
        wait(dut.knob_value_flat[6:0]==0);wait_frames(70);
        if(dut.u_core.sample_data!==0)begin $display("FAIL: ADC did not mute actual PCM");$finish;end
        adc.conversion0=26400;adc.conversion1=26400;
        wait(dut.knob_value_flat=={7'd127,7'd127});wait_frames(70);
        if(dut.u_core.bend_ratio!=73562 || dut.u_core.u_bank.g_voice[0].phase_inc<=23409859)begin
            $display("FAIL: ADC did not bend oscillator");$finish;end
        held_gain=dut.u_core.master_gain;held_ratio=dut.u_core.bend_ratio;
        adc.connected=0;wait(dut.param_fault);wait_frames(70);
        if(dut.u_core.master_gain!=held_gain || dut.u_core.bend_ratio!=held_ratio)begin $display("FAIL: ADC fault corrupted sound parameters");$finish;end
        adc.conversion1=13200;adc.connected=1;
        wait(dut.param_ready && !dut.param_fault && dut.knob_value_flat=={7'd64,7'd127});wait_frames(70);
        if(dut.u_core.bend_ratio!=65536)begin $display("FAIL: ADC recovery");$finish;end
        rst_n=0;repeat(8)@(negedge clk);
        if(dut.u_core.master_gain!=65536 || dut.u_core.bend_ratio!=65536)begin $display("FAIL: reset defaults");$finish;end
        $display("PASS tb_performance_adc: bit-level I2C/actual audio mute/bend/fault hold/recovery/reset; accelerated ADC settings");$finish;
    end
    initial begin #200000000;$display("FAIL: ADC timeout");$finish;end
endmodule
