`timescale 1ns/1ps

module poly_adsr_case #(
    parameter integer CASE_ID=0, A=96, D=24000, S=6554, R=5760, SHIFT=5
) (output reg done=0);
    reg clk=0, rst_n=0, request=0;
    reg [3:0] gates=0, triggers=0;
    reg [27:0] notes={7'd72,7'd67,7'd64,7'd60};
    reg [27:0] velocities={4{7'd127}};
    wire [3:0] active, released;
    wire [67:0] levels;
    wire sounding, valid, clipped;
    wire signed [15:0] sample;
    always #10 clk=~clk;
    voice_bank_adsr #(
        .ATTACK_SAMPLES(A),.DECAY_SAMPLES(D),.SUSTAIN_LEVEL(S),
        .RELEASE_SAMPLES(R),.MIX_SHIFT(SHIFT)
    ) dut (
        .clk(clk),.rst_n(rst_n),.sample_request(request),
        .voice_gate(gates),.voice_retrigger(triggers),
        .voice_note_flat(notes),.voice_velocity_flat(velocities),.voice_timbre(4'b0000),
        .release_done(released),.voice_active(active),.env_level_flat(levels),
        .sounding(sounding),.sample_data(sample),.sample_valid(valid),.sample_clipped(clipped)
    );
    localparam integer AN=(A==0)?1:A, DN=(D==0)?1:D, RN=(R==0)?1:R;
    localparam integer SN=(S>65536)?65536:S;
    integer level[4], state[4], segment[4], start_level[4], age[4];
    reg sampled_gate[4], pending_trigger[4];
    reg [31:0] phase[4];
    integer raw_queue[4], voice_sample[4], scaled_sample[4];
    integer velocity_queue[4], velocity_voice[4];
    reg mixed_nonzero[4];
    reg raw_ready=0, voice_ready=0, mix_ready=0;
    reg expected_valid, expected_clip;
    reg [3:0] expected_active, expected_released;
    integer expected_sample=0, total, shifted, step_inc, raw, v;
    integer clocks=0, samples=0, positive=0, negative=0, clips=0, resets=0;
    integer fd=0, i, duration_samples;
    reg [31:0] random_state=32'h951b4a3d;
    reg [2047:0] trace_path;
    real angle, sine_value;

    // 闭式直线参考：按段起点和采样年龄计算，不照搬 RTL 商/余数推进。
    task ramp(input integer voice, kind, endpoint, duration, input bit restart);
        reg [63:0] distance_product;
        begin
            if(restart || segment[voice]!=kind) begin
                segment[voice]=kind; start_level[voice]=level[voice]; age[voice]=0;
            end
            age[voice]++;
            if(endpoint>=start_level[voice]) begin
                distance_product=endpoint-start_level[voice];
                distance_product=distance_product*age[voice];
                level[voice]=start_level[voice]+distance_product/duration;
            end else begin
                distance_product=start_level[voice]-endpoint;
                distance_product=distance_product*age[voice];
                level[voice]=start_level[voice]-distance_product/duration;
            end
            state[voice]=kind;
            if(age[voice]==duration) state[voice]=(kind==1)?2:((kind==2)?3:0);
        end
    endtask
    function integer apply_gain(input integer s, gain);
        apply_gain=$rtoi($floor(s*1.0*gain/65536.0));
    endfunction

    // 每个 clk 检查数据、valid、包络和反馈，包含无请求拍与连续请求。
    always @(posedge clk) if(!done) begin
        expected_clip=0;
        if(!rst_n) begin
            raw_ready=0; voice_ready=0; mix_ready=0;
            expected_valid=0; expected_sample=0;
            expected_active=0; expected_released=15; resets++;
            for(v=0;v<4;v++) begin
                level[v]=0; state[v]=0; segment[v]=0; start_level[v]=0; age[v]=0;
                sampled_gate[v]=0; pending_trigger[v]=0; phase[v]=0;
                raw_queue[v]=0; voice_sample[v]=0; scaled_sample[v]=0;
                velocity_queue[v]=0; velocity_voice[v]=0; mixed_nonzero[v]=0;
            end
        end else begin
            expected_valid=mix_ready;
            if(mix_ready) begin
                total=0;
                for(v=0;v<4;v++) begin
                    total+=scaled_sample[v];
                    mixed_nonzero[v]=(scaled_sample[v]!=0);
                end
                shifted=$rtoi($floor(total*1.0/(2.0**SHIFT)));
                if(shifted>32767) begin expected_sample=32767; expected_clip=1; end
                else if(shifted< -32768) begin expected_sample= -32768; expected_clip=1; end
                else expected_sample=shifted;
            end
            mix_ready=voice_ready; voice_ready=raw_ready; raw_ready=request;
            for(v=0;v<4;v++) begin
                if(mix_ready)
                    scaled_sample[v]=apply_gain(voice_sample[v],
                        (velocity_voice[v]==127)?65536:velocity_voice[v]*512);
                if(voice_ready) begin
                    voice_sample[v]=raw_queue[v]; velocity_voice[v]=velocity_queue[v];
                end
                if(request) begin
                    if(!gates[v]) begin
                        if(level[v]==0) begin state[v]=0; segment[v]=0; end
                        else ramp(v,4,0,RN,0);
                    end else if(triggers[v] || pending_trigger[v] || !sampled_gate[v] || state[v]==0)
                        ramp(v,1,65536,AN,1);
                    else if(state[v]==1) ramp(v,1,65536,AN,0);
                    else if(state[v]==2) ramp(v,2,SN,DN,0);
                    else begin level[v]=SN; state[v]=3; segment[v]=0; end
                    sampled_gate[v]=gates[v]; pending_trigger[v]=0;
                    angle=6.283185307179586*(phase[v]>>22)/1024.0;
                    sine_value=32767.0*$sin(angle);
                    raw=(sine_value>=0)?$rtoi(sine_value+0.5):$rtoi(sine_value-0.5);
                    raw_queue[v]=apply_gain(raw,level[v]);
                    velocity_queue[v]=velocities[v*7 +: 7];
                    step_inc=$rtoi($floor(440.0*(2.0**((notes[v*7 +: 7]-69.0)/12.0))*
                                        4294967296.0/48000.0+0.5));
                    // 相位保留 32 位，累加自然回绕模 2^32，与真实 DDS 一致。
                    phase[v]=phase[v]+step_inc;
                end else if(triggers[v]) pending_trigger[v]=1;
                expected_active[v]=gates[v] || state[v]!=0 ||
                    (voice_ready && voice_sample[v]!=0) ||
                    (mix_ready && scaled_sample[v]!=0) || mixed_nonzero[v];
                expected_released[v]=!gates[v] && !expected_active[v];
            end
        end
        #1;
        if($signed(sample)!==expected_sample || valid!==expected_valid || clipped!==expected_clip ||
           active!==expected_active || released!==expected_released || sounding!==( |expected_active))
            $fatal(1,"poly case=%0d clock=%0d sample=%0d/%0d valid=%b/%b active=%b/%b done=%b/%b",
                   CASE_ID,clocks,$signed(sample),expected_sample,valid,expected_valid,
                   active,expected_active,released,expected_released);
        for(v=0;v<4;v++)
            if(levels[v*17 +: 17]!==level[v]) $fatal(1,"voice %0d envelope crossed lanes",v);
        if(dut.gain_valid!=={4{mix_ready}}) $fatal(1,"voice valid lanes differ");
        if(fd) $fdisplay(fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
            rst_n,request,gates,triggers,notes,velocities,$signed(sample),valid,clipped,
            active,released,sounding,levels[16:0],levels[33:17],levels[50:34],levels[67:51]);
        clocks++;
        if(valid) begin
            samples++; if(sample>0) positive++; if(sample<0) negative++; if(clipped) clips++;
        end
    end

    task cycle(input bit reset_n, en, input logic [3:0] g, tr);
        @(negedge clk); rst_n=reset_n; request=en; gates=g; triggers=tr;
        @(posedge clk); #2;
    endtask
    task tick(input logic [3:0] g, tr);
        cycle(1,1,g,tr);
        repeat(3) cycle(1,0,g,0);
    endtask
    initial begin
        if((CASE_ID==0 && $value$plusargs("POLY_TRACE_DEFAULT=%s",trace_path)) ||
           (CASE_ID==1 && $value$plusargs("POLY_TRACE_BOUNDARY=%s",trace_path))) begin
            fd=$fopen(trace_path,"w");
            if(!fd) $fatal(1,"cannot open poly trace");
            $fdisplay(fd,"# poly_adsr v1 A=%0d D=%0d S=%0d R=%0d SHIFT=%0d",A,D,S,R,SHIFT);
        end
        cycle(0,1,15,15); // 复位同时出现请求、保持和触发
        repeat(5) tick(0,0);
        repeat(32) tick(1,0); // 只有声部 0 起音
        repeat(20) tick(0,0); // 起音途中提前松键
        repeat(100) tick(3,0); // 声部 0 重按，声部 1 独立起音
        velocities={7'd127,7'd64,7'd0,7'd127};
        tick(15,15);
        duration_samples=(CASE_ID==0)?30000:80;
        repeat(duration_samples) tick(15,0);
        for(i=0;i<4;i++)
            if(levels[i*17 +: 17]!==SN) $fatal(1,"sustain not reached");
        notes={4{7'd69}}; velocities={4{7'd127}};
        repeat(400) tick(15,0); // 短参数满增益覆盖正负饱和
        cycle(1,0,15,5); // 两次采样之间的独立触发脉冲
        cycle(1,0,15,0);
        repeat(140) tick(15,0);
        repeat(30) tick(14,0); // 只释放声部 0
        notes[13:7]=7'd76;
        tick(14,2); // 模拟 C 把新音分给仍保持的声部 1，并明确重触发
        repeat(100) tick(14,0);
        // 请求后立刻改变增益输入；已在流水线中的样本仍使用原快照。
        cycle(1,1,15,0);
        velocities=0;
        repeat(4) cycle(1,0,15,0);
        // 逐拍连续请求，不允许增益或音符串到前一个样本。
        for(i=0;i<300;i++) begin
            velocities=(i[0])?{4{7'd127}}:{7'd0,7'd1,7'd64,7'd126};
            notes={7'd127,7'd0,7'd69,7'd60};
            cycle(1,1,15,(i%41==0)?4'b0101:4'b0000);
        end
        cycle(0,1,15,15); // 发声和待输出样本一起复位
        for(i=0;i<3000;i++) begin
            random_state=random_state*32'd1664525+32'd1013904223;
            notes=random_state[27:0];
            velocities=(random_state^32'h7263bc19)&28'hfffffff;
            cycle(i%997!=0,random_state[31],random_state[27:24],random_state[23:20]);
        end
        repeat(RN+8) tick(0,0);
        repeat(5) cycle(1,0,0,0);
        if(sample!==0 || released!==15 || active!==0 || levels!==0) $fatal(1,"final release not silent");
        if(CASE_ID==1) begin
            // 1 点释放也要等 R3 的零样本，不能在包络归零的 R0 抢先回收。
            cycle(0,1,15,15); notes={4{7'd69}}; velocities={4{7'd127}};
            repeat(20) cycle(1,1,15,0);
            cycle(1,1,0,0); if(released!==0) $fatal(1,"release early R0");
            cycle(1,0,0,0); if(released!==0) $fatal(1,"release early R1");
            cycle(1,0,0,0); if(released!==0) $fatal(1,"release early R2");
            cycle(1,0,0,0); if(released!==15) $fatal(1,"release late R3");
            cycle(1,0,0,0);
        end
        if(samples<1000 || positive==0 || negative==0 || resets<4) $fatal(1,"incomplete poly coverage");
        if(SHIFT==0 && clips==0) $fatal(1,"missing clipped output");
        if(SHIFT==5 && clips!=0) $fatal(1,"quiet output clipped");
        if(fd) begin
            $fdisplay(fd,"# completed clocks=%0d samples=%0d resets=%0d",clocks,samples,resets);
            $fclose(fd);
        end
        $display("poly case=%0d verified %0d clocks, %0d samples, %0d resets, %0d clips",
                 CASE_ID,clocks,samples,resets,clips);
        done=1;
    end
endmodule

module tb_voice_bank_adsr;
    wire default_done, boundary_done;
    poly_adsr_case default_case(default_done);
    poly_adsr_case #(.CASE_ID(1),.A(0),.D(1),.S(70000),.R(1),.SHIFT(0))
        boundary_case(boundary_done);
    initial begin
        wait(default_done && boundary_done);
        #3; $display("PASS: voice_bank_adsr four independent envelopes, triggers, pipeline and mix.");
        $finish;
    end
    initial begin #50000000; $fatal(1,"poly ADSR timeout"); end
endmodule
