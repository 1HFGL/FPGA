`timescale 1ns/1ps
// 与Git中修改前的独立核心比较。参考文件仅存在build，不增加第二套发布RTL。
module tb_architecture_equivalence;
    reg clk=0,rst_n=0,request=0;
    reg [15:0] gate=0,trigger=0,preset=0;
    reg [111:0] notes=0,velocity={16{7'd100}};
    reg [16:0] gain=65536,ratio=65536;
    wire [15:0] active_a,active_b,release_a,release_b,selected_a,selected_b;
    wire [271:0] env_a,env_b;
    wire sound_a,sound_b,busy_a,busy_b,valid_a,valid_b,clip_a,clip_b,over_a,over_b;
    wire signed [15:0] sample_a,sample_b;
    always #10 clk=~clk;
    voice_bank_music_pipe dut(.clk(clk),.rst_n(rst_n),.sample_request(request),
        .global_gain_q16(gain),.pitch_ratio_q16(ratio),.voice_gate(gate),.voice_retrigger(trigger),
        .voice_instrument(preset),.voice_note_flat(notes),.voice_velocity_flat(velocity),
        .voice_active(active_a),.release_done(release_a),.instrument_active(selected_a),.env_level_flat(env_a),
        .sounding(sound_a),.busy(busy_a),.sample_data(sample_a),.sample_valid(valid_a),.sample_clipped(clip_a),.overrun(over_a));
    voice_bank_music_pipe_original reference(.clk(clk),.rst_n(rst_n),.sample_request(request),
        .global_gain_q16(gain),.pitch_ratio_q16(ratio),.voice_gate(gate),.voice_retrigger(trigger),
        .voice_instrument(preset),.voice_note_flat(notes),.voice_velocity_flat(velocity),
        .voice_active(active_b),.release_done(release_b),.instrument_active(selected_b),.env_level_flat(env_b),
        .sounding(sound_b),.busy(busy_b),.sample_data(sample_b),.sample_valid(valid_b),.sample_clipped(clip_b),.overrun(over_b));
    integer cycle=0,issued=0,samples=0,nonzero=0,frame,v,p,block;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(rst_n && request && !busy_a)issued=cycle;
        #1;
        if(rst_n)begin
            if({active_a,release_a,selected_a,env_a,sound_a,busy_a,valid_a,clip_a,over_a,sample_a}!==
               {active_b,release_b,selected_b,env_b,sound_b,busy_b,valid_b,clip_b,over_b,sample_b})begin
                $display("FAIL architecture audio mismatch cycle=%0d samples=%0d",cycle,samples);$finish;
            end
            if(valid_a)begin
                if(cycle-issued!=923)begin $display("FAIL architecture latency %0d",cycle-issued);$finish;end
                samples=samples+1;if(sample_a!=0)nonzero=nonzero+1;
            end
        end
    end
    task tick;
        begin
            @(negedge clk);request=1;
            @(negedge clk);request=0;trigger=0;
            repeat(1041)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        // 全部128个音号、两音色都实际进入16声部调度，32帧含完整吉他起音。
        for(p=0;p<2;p=p+1)begin
            preset=p?16'hffff:16'h0000;
            for(block=0;block<8;block=block+1)begin
                gate=16'hffff;trigger=16'hffff;
                for(v=0;v<16;v=v+1)notes[v*7+:7]=block*16+v;
                repeat(32)tick;
            end
        end
        preset=16'haaaa;trigger=16'hffff;
        for(v=0;v<16;v=v+1)begin notes[v*7+:7]=48+v;velocity[v*7+:7]=v*8+7;end
        repeat(64)tick;
        gain=0;repeat(8)tick;
        if(sample_a!==0)begin $display("FAIL architecture mute");$finish;end
        gain=32768;ratio=58386;repeat(32)tick;
        gain=65536;ratio=73562;repeat(32)tick;
        // 忙时下一次触发与音色变化，以及忙时请求故障。
        @(negedge clk);request=1;@(negedge clk);request=0;
        repeat(123)@(negedge clk);trigger=16'h0101;preset=~preset;
        @(negedge clk);trigger=0;
        repeat(919)@(negedge clk);repeat(8)tick;
        gate=0;ratio=65536;repeat(4200)tick;
        if(sound_a || release_a!==16'hffff)begin $display("FAIL architecture tail drain");$finish;end
        gate=1;trigger=1;tick;
        @(negedge clk);request=1;@(negedge clk);request=0;
        repeat(20)@(negedge clk);request=1;@(negedge clk);request=0;
        repeat(10)@(negedge clk);
        if(!over_a)begin $display("FAIL architecture missing overrun");$finish;end
        rst_n=0;gate=0;trigger=0;repeat(4)@(negedge clk);rst_n=1;tick;
        if(over_a || sample_a!==0 || samples<4800 || nonzero<400)begin
            $display("FAIL architecture reset/stimulus samples=%0d nonzero=%0d",samples,nonzero);$finish;
        end
        $display("PASS tb_architecture_equivalence: %0d exact samples, %0d nonzero, all128/two presets/full16/R923/tails/control/reset",samples,nonzero);$finish;
    end
    initial begin #150000000;$display("FAIL architecture audio timeout");$finish;end
endmodule
