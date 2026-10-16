`timescale 1ns/1ps
// 数字合成检查：每声部实际非零样本、正负弯音频率、静音/增益、尾音与代次。
// 加速请求仅用于算法验证，样本序列按48kHz解释，不作为整机延迟证据。
module tb_performance_bank;
    reg clk=0,rst_n=0,request=0,kv=0;
    reg [13:0] knobs={7'd64,7'd127};
    reg [15:0] gates=0;
    reg [255:0] ids=0;
    reg [111:0] notes=0;
    wire [16:0] gain;
    wire [17:0] ratio;
    wire [15:0] done,active;
    wire [255:0] completed;
    wire [271:0] env;
    wire signed [15:0] dry,out;
    wire valid,ov;
    integer i,n,count,last_sign,up,mid,down,again,heard[0:15],value,expected;
    reg [15:0] clip_seen=0;
    piano_controls ctrl(.clk(clk),.rst_n(rst_n),.sample_request(request),
        .knob_value_flat(knobs),.knob_valid(kv),.param_ready(1'b1),.param_fault(1'b0),
        .master_gain(gain),.bend_ratio(ratio));
    voice_bank_adsr #(.VOICES(16),.ENABLE_CONTROLS(1),.ROM_FILE("rtl/rom/sine_1024.mem"),
        .BRIGHT_ROM_FILE("rtl/rom/sine_1024.mem"),.ATTACK_SAMPLES(4),.DECAY_SAMPLES(4),
        .SUSTAIN_LEVEL(65536),.RELEASE_SAMPLES(128),.MIX_SHIFT(5)) dut(
        .clk(clk),.rst_n(rst_n),.sample_request(request),.voice_gate(gates),.voice_retrigger(16'd0),
        .voice_note_flat(notes),.voice_velocity_flat({16{7'd100}}),.release_done(done),
        .voice_active(active),.env_level_flat(env),.sounding(),.sample_data(dry),.sample_valid(valid),
        .sample_clipped(),.voice_timbre(16'd0),.voice_trigger_id_flat(ids),
        .release_trigger_id_flat(completed),.bend_ratio(ratio));
    sample_gain master(.clk(clk),.rst(!rst_n),.in_valid(valid),.sample_in(dry),
        .gain(gain),.sample_out(out),.out_valid(ov));
    always #10 clk=~clk;
    task tick;
        begin
            @(negedge clk);request=1;@(negedge clk);request=0;
            repeat(6) @(negedge clk);
            if(completed!==ids) begin $display("FAIL: generation confirmation");$finish;end
        end
    endtask
    task set_knobs;
        input [6:0] vol,bend;
        begin
            @(negedge clk);knobs={bend,vol};kv=1;@(negedge clk);kv=0;
            repeat(66) tick;
        end
    endtask
    task frequency;
        output integer crossings;
        integer j;
        begin
            crossings=0;last_sign=0;
            for(j=0;j<9600;j=j+1) begin
                tick;
                if(dry>0 && last_sign<=0)crossings=crossings+1;
                if(dry!=0)last_sign=dry;
            end
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(i=0;i<16;i=i+1)begin notes[i*7+:7]=48+i;ids[i*16+:16]=1;heard[i]=0;end
        gates=16'hffff;
        for(n=0;n<500;n=n+1)begin
            tick;
            for(i=0;i<16;i=i+1)if($signed(dut.gain_samples[i*16+:16])!=0)heard[i]=heard[i]+1;
        end
        for(i=0;i<16;i=i+1)if(heard[i]<100)begin $display("FAIL: silent independent voice %0d",i);$finish;end
        gates=1;notes[6:0]=60;
        repeat(140)tick;
        set_knobs(127,64);frequency(mid);
        set_knobs(127,127);frequency(up);
        if(ratio!=73562)begin $display("FAIL: upper ratio %0d",ratio);$finish;end
        set_knobs(127,0);frequency(down);
        if(ratio!=58386)begin $display("FAIL: lower ratio %0d",ratio);$finish;end
        set_knobs(127,63);frequency(again);
        if(mid<51 || mid>54 || up<58 || up>60 || down<46 || down>48 || again<51 || again>54)begin
            $display("FAIL: observed frequency crossings mid/up/down/return=%0d/%0d/%0d/%0d",mid,up,down,again);$finish;
        end
        set_knobs(64,64);
        for(n=0;n<100;n=n+1)begin
            tick;expected=($signed(dry)*$signed({1'b0,gain}))>>>16;
            if(out!==expected)begin $display("FAIL: output volume %0d expected %0d gain %0d",out,expected,gain);$finish;end
        end
        set_knobs(0,64);
        for(n=0;n<50;n=n+1)begin tick;if(out!==0)begin $display("FAIL: mute");$finish;end end
        set_knobs(127,64);
        gates=0;repeat(20)tick;
        if(done[0])begin $display("FAIL: early tail release");$finish;end
        set_knobs(127,127);
        if(dut.g_voice[0].phase_inc<=23409859)begin $display("FAIL: bend not applied to tail");$finish;end
        repeat(150)tick;
        if(done!==16'hffff || active!==0)begin $display("FAIL: tail completion");$finish;end
        // 在两请求之间重触发并释放：确认新代次后才允许回收。
        @(negedge clk);ids[15:0]=2;
        if(done[0])begin #1;if(done[0])begin $display("FAIL: stale completion accepted");$finish;end end
        tick;if(!done[0] || completed[15:0]!=2)begin $display("FAIL: short note completion generation");$finish;end
        @(negedge clk);rst_n=0;repeat(5)@(negedge clk);
        if(active!==0 || out!==0)begin $display("FAIL: reset");$finish;end
        // 连续请求：一个起音代次只能触发一次，R1~R4四点后恰好到峰值。
        rst_n=1;gates=1;ids=0;ids[15:0]=1;notes[6:0]=60;request=1;
        repeat(5)@(negedge clk);
        if(env[16:0]!=65536 || completed[15:0]!=1 ||
           dut.g_voice[0].u_voice.u_phase_acc.phase!=32'd93639436)begin
            $display("FAIL: continuous request control/phase alignment env=%0d phase=%0d",env[16:0],dut.g_voice[0].u_voice.u_phase_acc.phase);$finish;
        end
        request=0;
        $display("PASS tb_performance_bank: 16 audible voices; crossings=%0d/%0d/%0d/%0d; actual volume/bend/tails/generation/reset",mid,up,down,again);
        $finish;
    end
    initial begin #30000000;$display("FAIL: bank timeout");$finish;end
endmodule
