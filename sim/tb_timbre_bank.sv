`timescale 1ns/1ps

module timbre_bank_case #(
    parameter integer CASE_ID=0, A=8, D=17, S=20000, R=11, SHIFT=5
) (output reg done=0);
    reg clk=0, rst_n=0, request=0;
    reg [3:0] gates=0, triggers=0, timbres=0;
    reg [27:0] notes=0;
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
        .voice_gate(gates),.voice_retrigger(triggers),.voice_timbre(timbres),
        .voice_note_flat(notes),.voice_velocity_flat(velocities),
        .release_done(released),.voice_active(active),.env_level_flat(levels),
        .sounding(sounding),.sample_data(sample),.sample_valid(valid),.sample_clipped(clipped)
    );
    wire [3:0] observed_timbre;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin: monitor_lane
        assign observed_timbre[lane]=dut.g_voice[lane].u_voice.active_timbre;
    end endgenerate
    localparam integer AN=(A==0)?1:A, DN=(D==0)?1:D, RN=(R==0)?1:R;
    localparam integer SN=(S>65536)?65536:S;
    integer level[4], state[4], segment[4], start_level[4], age[4];
    reg sampled_gate[4], pending_trigger[4], active_timbre[4], pending_timbre[4];
    reg new_note;
    integer accepted_soft=0, accepted_bright=0, deferred=0, replaced=0, override_now=0;
    integer held_ignored=0, tail_ignored=0, fallback=0, mixed_colors=0, discarded=0;
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
                active_timbre[v]=0; pending_timbre[v]=0;
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
                    // 先按“收到一个新音符事件”决定音色，再推进独立的数学包络。
                    new_note=gates[v] && (triggers[v] || pending_trigger[v] ||
                                           !sampled_gate[v] || state[v]==0);
                    if(new_note) begin
                        if(triggers[v]) begin
                            if(pending_trigger[v]) override_now++;
                            active_timbre[v]=timbres[v];
                        end else if(pending_trigger[v]) begin
                            deferred++; active_timbre[v]=pending_timbre[v];
                        end else active_timbre[v]=timbres[v];
                        if(active_timbre[v]) accepted_bright++; else accepted_soft++;
                    end else if(timbres[v]!=active_timbre[v]) begin
                        if(gates[v]) held_ignored++;
                        else if(level[v]!=0) tail_ignored++;
                    end
                    if(!gates[v] && pending_trigger[v]) discarded++;
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
                    step_inc=$rtoi($floor(440.0*(2.0**((notes[v*7 +: 7]-69.0)/12.0))*
                                        4294967296.0/48000.0+0.5));
                    if(active_timbre[v] && step_inc<32'h20000000)
                        sine_value=32767.0*(8.0*$sin(angle)+4.0*$sin(2.0*angle)+
                                           2.0*$sin(3.0*angle)+$sin(4.0*angle))/15.0;
                    else begin
                        sine_value=32767.0*$sin(angle);
                        if(active_timbre[v] && level[v]!=0) fallback++;
                    end
                    raw=(sine_value>=0)?$rtoi(sine_value+0.5):$rtoi(sine_value-0.5);
                    raw_queue[v]=apply_gain(raw,level[v]);
                    velocity_queue[v]=velocities[v*7 +: 7];
                    // 相位保留 32 位，累加自然回绕模 2^32，与真实 DDS 一致。
                    phase[v]=phase[v]+step_inc;
                end else if(triggers[v]) begin
                    if(pending_trigger[v]) replaced++;
                    pending_trigger[v]=1; pending_timbre[v]=timbres[v];
                end
                expected_active[v]=gates[v] || state[v]!=0 ||
                    (voice_ready && voice_sample[v]!=0) ||
                    (mix_ready && scaled_sample[v]!=0) || mixed_nonzero[v];
                expected_released[v]=!gates[v] && !expected_active[v];
            end
        end
        if(request && rst_n && gates==15 &&
           (active_timbre[0] || active_timbre[1] || active_timbre[2] || active_timbre[3]) &&
           !(active_timbre[0] && active_timbre[1] && active_timbre[2] && active_timbre[3])) mixed_colors++;
        #1;
        if($signed(sample)!==expected_sample || valid!==expected_valid || clipped!==expected_clip ||
           active!==expected_active || released!==expected_released || sounding!==( |expected_active))
            $fatal(1,"timbre case=%0d clock=%0d sample=%0d/%0d valid=%b/%b active=%b/%b done=%b/%b",
                   CASE_ID,clocks,$signed(sample),expected_sample,valid,expected_valid,
                   active,expected_active,released,expected_released);
        for(v=0;v<4;v++)
            if(levels[v*17 +: 17]!==level[v]) $fatal(1,"voice %0d envelope crossed lanes",v);
        for(v=0;v<4;v++)
            if(observed_timbre[v]!==active_timbre[v])
                $fatal(1,"case=%0d clock=%0d voice=%0d timbre adoption actual=%b expected=%b",CASE_ID,clocks,v,observed_timbre[v],active_timbre[v]);
        if(dut.gain_valid!=={4{mix_ready}}) $fatal(1,"voice valid lanes differ");
        if(fd) $fdisplay(fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
            rst_n,request,gates,triggers,notes,velocities,timbres,$signed(sample),valid,clipped,
            active,released,sounding,levels[16:0],levels[33:17],levels[50:34],levels[67:51],observed_timbre);
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
        if((CASE_ID==0 && $value$plusargs("TIMBRE_TRACE_SHORT=%s",trace_path)) ||
           (CASE_ID==1 && $value$plusargs("TIMBRE_TRACE_BOUNDARY=%s",trace_path)) ||
           (CASE_ID==2 && $value$plusargs("TIMBRE_TRACE_ZERO=%s",trace_path))) begin
            fd=$fopen(trace_path,"w");
            if(!fd) $fatal(1,"cannot open timbre trace");
            $fdisplay(fd,"# timbre_bank v1 A=%0d D=%0d S=%0d R=%0d SHIFT=%0d",A,D,S,R,SHIFT);
        end
        cycle(0,1,15,15); // 同时复位、请求、触发，必须全部清除。
        notes={7'd72,7'd67,7'd64,7'd60}; // 复位期间明确改变输入，兼容事件仿真初始化。
        repeat(5) tick(0,0);
        timbres=4'b1010;
        repeat(100) tick(15,0); // 四声部同时采用柔/亮/柔/亮。
        timbres=4'b0101;
        repeat(80) tick(15,0); // 保持键时变更选择，不改变现有音色。
        repeat(4) tick(0,0);   // 正在释放时改变选择，同样保留尾音音色。
        timbres=4'b1111;
        repeat(RN+5) tick(0,0);
        timbres=4'b1010; tick(15,0); // 起音中提前释放，S=0 也有非零尾音。
        timbres=4'b0101; repeat(RN+3) tick(0,0);
        timbres=4'b0101;
        repeat(80) tick(15,0); // 全部回收后的自然起音采用新音色。
        timbres=4'b1010;
        tick(15,15); // 相同音符保持期间，明确 retrigger 才更换音色。
        repeat(50) tick(15,0);

        // 暂存脉冲当拍的音色，随后选择输入改变也不能污染它。
        timbres=4'b0101; cycle(1,0,15,15);
        timbres=4'b1010; cycle(1,0,15,0);
        tick(15,0); repeat(40) tick(15,0);
        // 同一采样间隔多个脉冲合并，最近脉冲的音色获胜。
        timbres=4'b0000; cycle(1,0,15,15);
        timbres=4'b1111; cycle(1,0,15,15);
        timbres=4'b0000; tick(15,0); repeat(40) tick(15,0);
        // 采样当拍的新脉冲优先于此前暂存的脉冲。
        timbres=4'b1111; cycle(1,0,15,15);
        timbres=4'b0000; tick(15,15); repeat(40) tick(15,0);

        // 非采样拍的 gate=0 不得丢弃 pending；采样到 gate=0 才丢弃。
        timbres=4'b1111; cycle(1,0,0,15);
        timbres=4'b0000; cycle(1,0,15,0);
        tick(15,0); repeat(40) tick(15,0);
        timbres=4'b0000; cycle(1,0,15,15);
        timbres=4'b1111; tick(0,0);
        repeat(RN+4) tick(0,0);
        timbres=4'b1010; tick(15,0); repeat(50) tick(15,0);

        notes[13:7]=7'd76; timbres[1]=~timbres[1];
        tick(15,2); repeat(60) tick(15,0); // 第五音模拟：替换仍保持的槽 1。
        // 全音符范围包含阈值两侧（114/115）和最高音符 127。
        notes={7'd127,7'd115,7'd114,7'd69}; timbres=15;
        tick(15,15); repeat(300) tick(15,0);
        // 请求后立即改变输入；已有样本仍使用原音色和力度快照。
        cycle(1,1,15,0); timbres=0; velocities=0;
        repeat(5) cycle(1,0,15,0);
        for(i=0;i<500;i++) begin
            timbres=i[3:0];
            velocities=(i[0])?{4{7'd127}}:{7'd0,7'd1,7'd64,7'd126};
            notes={7'd127,7'd115,7'd114,7'd60};
            cycle(1,1,15,(i%31==0)?4'b0101:4'b0000);
        end
        // 同相满幅检查饱和；两类符号都应出现。
        cycle(0,1,15,15); notes={4{7'd69}}; velocities={4{7'd127}}; timbres=0;
        repeat(500) tick(15,0);
        timbres=15; cycle(1,0,15,15);
        cycle(0,0,15,0); // reset 清除未消费的触发与音色快照。
        timbres=0; repeat(50) tick(15,0);
        for(i=0;i<5000;i++) begin
            random_state=random_state*32'd1664525+32'd1013904223;
            notes=random_state[27:0];
            velocities=(random_state^32'h7263bc19)&28'hfffffff;
            timbres=random_state[7:4];
            cycle(i%997!=0,random_state[31],random_state[27:24],random_state[23:20]);
        end
        repeat(RN+8) tick(0,0);
        repeat(20) tick(0,0); // 长空闲仍维持静音、释放完成和正确 valid。
        repeat(5) cycle(1,0,0,0);
        if(sample!==0 || released!==15 || active!==0 || levels!==0) $fatal(1,"final release not silent");
        if(samples<2000 || positive==0 || negative==0 || resets<4) $fatal(1,"incomplete timbre coverage");
        if(SHIFT==0 && clips==0) $fatal(1,"missing clipped output");
        if(SHIFT==5 && clips!=0) $fatal(1,"quiet output clipped");
        if(accepted_soft==0 || accepted_bright==0 || deferred==0 || replaced==0 || override_now==0 ||
           held_ignored==0 || tail_ignored==0 || fallback==0 || mixed_colors==0 || discarded==0)
            $fatal(1,"missing timbre adoption/fallback coverage");
        $display("timbre coverage soft=%0d bright=%0d deferred=%0d replaced=%0d override=%0d held=%0d tail=%0d fallback=%0d mixed=%0d discarded=%0d",
                 accepted_soft,accepted_bright,deferred,replaced,override_now,held_ignored,tail_ignored,fallback,mixed_colors,discarded);
        if(fd) begin
            $fdisplay(fd,"# completed clocks=%0d samples=%0d resets=%0d",clocks,samples,resets);
            $fclose(fd);
        end
        $display("timbre case=%0d verified %0d clocks, %0d samples, %0d resets, %0d clips",
                 CASE_ID,clocks,samples,resets,clips);
        done=1;
    end
endmodule

module tb_timbre_bank;
    wire default_done, boundary_done, zero_done;
    timbre_bank_case default_case(default_done);
    timbre_bank_case #(.CASE_ID(1),.A(0),.D(1),.S(70000),.R(1),.SHIFT(0))
        boundary_case(boundary_done);
    timbre_bank_case #(.CASE_ID(2),.S(0)) zero_case(zero_done);
    initial begin
        wait(default_done && boundary_done && zero_done);
        #3; $display("PASS: tb_timbre_bank mixed voices, per-note timbre snapshots, pending triggers, high-note fallback and R3 pipeline.");
        $finish;
    end
    initial begin #50000000; $fatal(1,"timbre bank timeout"); end
endmodule
