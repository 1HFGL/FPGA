`timescale 1ns/1ps

module instrument_bank_case #(
    parameter integer CASE_ID=0, SHIFT=5,
    parameter [31:0] GA=8, GD=17, GS=0, GR=11,
                     SA=13, SD=9, SS=40000, SR=19, GT=23, ST=31
) (output reg done=0);
    reg clk=0, rst_n=0, request=0;
    reg [3:0] gates=0, triggers=0, instruments=0;
    reg [27:0] notes=0;
    reg [27:0] velocities={4{7'd127}};
    wire [3:0] active, released;
    wire [67:0] levels, tones;
    wire [3:0] observed_instrument;
    wire sounding, valid, clipped;
    wire signed [15:0] sample;
    always #10 clk=~clk;
    voice_bank_instruments #(
        .G_ATTACK(GA),.G_DECAY(GD),.G_SUSTAIN(GS),.G_RELEASE(GR),
        .S_ATTACK(SA),.S_DECAY(SD),.S_SUSTAIN(SS),.S_RELEASE(SR),
        .G_TONE_SAMPLES(GT),.S_TONE_SAMPLES(ST),.MIX_SHIFT(SHIFT)
    ) dut (
        .clk(clk),.rst_n(rst_n),.sample_request(request),
        .voice_gate(gates),.voice_retrigger(triggers),.voice_instrument(instruments),
        .voice_note_flat(notes),.voice_velocity_flat(velocities),
        .release_done(released),.voice_active(active),.env_level_flat(levels),
        .instrument_active(observed_instrument),.tone_level_flat(tones),
        .sounding(sounding),.sample_data(sample),.sample_valid(valid),.sample_clipped(clipped)
    );
    localparam integer RN=(CASE_ID==3)?20:(GR>SR)?((GR==0)?1:GR):((SR==0)?1:SR);
    reg [31:0] an, dn, rn, tn;
    integer sn;
    integer tone_age[4], tone_level[4];
    integer level[4], state[4], segment[4], start_level[4], age[4];
    reg sampled_gate[4], pending_trigger[4], active_instrument[4], pending_instrument[4];
    reg new_note;
    integer accepted_guitar=0, accepted_strings=0, deferred=0, replaced=0, override_now=0;
    integer held_ignored=0, tail_ignored=0, fallback=0, mixed_colors=0, discarded=0;
    integer zero_held=0, positive_clip=0, negative_clip=0;
    reg [31:0] phase[4];
    integer raw_queue[4], shape_queue[4], voice_sample[4], scaled_sample[4];
    integer raw_env[4], shape_env[4];
    integer velocity_queue[4], velocity_shape[4], velocity_voice[4];
    reg mixed_nonzero[4];
    reg raw_ready=0, shape_ready=0, voice_ready=0, mix_ready=0;
    reg expected_valid, expected_clip;
    reg [3:0] expected_active, expected_released;
    integer expected_sample=0, total, shifted, step_inc, raw, base, full, v, h, weight;
    integer clocks=0, samples=0, positive=0, negative=0, clips=0, resets=0;
    integer fd=0, i, duration_samples;
    reg [31:0] random_state=32'h951b4a3d;
    reg [2047:0] trace_path;
    real angle, sine_value;

    // 闭式直线参考：按段起点和采样年龄计算，不照搬 RTL 商/余数推进。
    task ramp(input integer voice, kind, endpoint, input reg [31:0] duration, input bit restart);
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
            raw_ready=0; shape_ready=0; voice_ready=0; mix_ready=0;
            expected_valid=0; expected_sample=0;
            expected_active=0; expected_released=15; resets++;
            for(v=0;v<4;v++) begin
                level[v]=0; state[v]=0; segment[v]=0; start_level[v]=0; age[v]=0;
                sampled_gate[v]=0; pending_trigger[v]=0; phase[v]=0;
                active_instrument[v]=0; pending_instrument[v]=0;
                raw_queue[v]=0; shape_queue[v]=0; voice_sample[v]=0; scaled_sample[v]=0;
                raw_env[v]=0; shape_env[v]=0; tone_age[v]=0; tone_level[v]=65536;
                velocity_queue[v]=0; velocity_shape[v]=0; velocity_voice[v]=0; mixed_nonzero[v]=0;
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
            mix_ready=voice_ready; voice_ready=shape_ready; shape_ready=raw_ready; raw_ready=request;
            for(v=0;v<4;v++) begin
                if(mix_ready)
                    scaled_sample[v]=apply_gain(voice_sample[v],
                        (velocity_voice[v]==127)?65536:velocity_voice[v]*512);
                if(voice_ready) begin
                    voice_sample[v]=shape_queue[v]; velocity_voice[v]=velocity_shape[v];
                end
                if(shape_ready) begin
                    shape_queue[v]=raw_queue[v]; velocity_shape[v]=velocity_queue[v];
                    shape_env[v]=raw_env[v];
                end
                if(request) begin
                    // 先按“收到一个新音符事件”决定乐器预设，再推进独立的数学包络。
                    new_note=gates[v] && (triggers[v] || pending_trigger[v] ||
                                           !sampled_gate[v] || state[v]==0);
                    if(new_note) begin
                        if(triggers[v]) begin
                            if(pending_trigger[v]) override_now++;
                            active_instrument[v]=instruments[v];
                        end else if(pending_trigger[v]) begin
                            deferred++; active_instrument[v]=pending_instrument[v];
                        end else active_instrument[v]=instruments[v];
                        if(active_instrument[v]) accepted_strings++; else accepted_guitar++;
                        tone_age[v]=0;
                    end else if(instruments[v]!=active_instrument[v]) begin
                        if(gates[v]) begin held_ignored++; if(state[v]==3 && level[v]==0) zero_held++; end
                        else if(level[v]!=0) tail_ignored++;
                    end
                    an=active_instrument[v]?SA:GA; if(an==0) an=1;
                    dn=active_instrument[v]?SD:GD; if(dn==0) dn=1;
                    sn=active_instrument[v]?SS:GS; if(sn>65536) sn=65536;
                    rn=active_instrument[v]?SR:GR; if(rn==0) rn=1;
                    tn=active_instrument[v]?ST:GT; if(tn==0) tn=1;
                    if(!new_note && tone_age[v]<tn) tone_age[v]++;
                    if(active_instrument[v]) tone_level[v]=8192+(24576*tone_age[v])/tn;
                    else tone_level[v]=65536-(61440*tone_age[v])/tn;
                    if(!gates[v] && pending_trigger[v]) discarded++;
                    if(!gates[v]) begin
                        if(level[v]==0) begin state[v]=0; segment[v]=0; end
                        else ramp(v,4,0,rn,0);
                    end else if(triggers[v] || pending_trigger[v] || !sampled_gate[v] || state[v]==0)
                        ramp(v,1,65536,an,1);
                    else if(state[v]==1) ramp(v,1,65536,an,0);
                    else if(state[v]==2) ramp(v,2,sn,dn,0);
                    else begin level[v]=sn; state[v]=3; segment[v]=0; end
                    sampled_gate[v]=gates[v]; pending_trigger[v]=0;
                    angle=6.283185307179586*(phase[v]>>22)/1024.0;
                    step_inc=$rtoi($floor(440.0*(2.0**((notes[v*7 +: 7]-69.0)/12.0))*
                                        4294967296.0/48000.0+0.5));
                    sine_value=32767.0*$sin(angle);
                    raw=(sine_value>=0)?$rtoi(sine_value+0.5):$rtoi(sine_value-0.5);
                    base=$rtoi($floor(raw/2.0));
                    if(step_inc<32'h10000000) begin
                        sine_value=0.0;
                        for(h=1;h<=8;h++) begin
                            if(active_instrument[v]) case(h)
                                1:weight=16; 2:weight=6; 3:weight=3;
                                4,5:weight=2; default:weight=1;
                            endcase
                            else case(h)
                                1:weight=16; 2:weight=8; 3:weight=4;
                                5:weight=2; 6,7:weight=1; default:weight=0;
                            endcase
                            sine_value=sine_value+weight*$sin(h*angle);
                        end
                        sine_value=32767.0*sine_value/32.0;
                        full=(sine_value>=0)?$rtoi(sine_value+0.5):$rtoi(sine_value-0.5);
                    end else begin
                        full=base;
                        if(level[v]!=0) fallback++;
                    end
                    raw=base+apply_gain(full-base,tone_level[v]);
                    raw_queue[v]=apply_gain(raw,level[v]); raw_env[v]=level[v];
                    velocity_queue[v]=velocities[v*7 +: 7];
                    // 相位保留 32 位，累加自然回绕模 2^32，与真实 DDS 一致。
                    phase[v]=phase[v]+step_inc;
                end else if(triggers[v]) begin
                    if(pending_trigger[v]) replaced++;
                    pending_trigger[v]=1; pending_instrument[v]=instruments[v];
                end
                expected_active[v]=gates[v] || state[v]!=0 ||
                    (shape_ready && shape_env[v]!=0) ||
                    (voice_ready && voice_sample[v]!=0) ||
                    (mix_ready && scaled_sample[v]!=0) || mixed_nonzero[v];
                expected_released[v]=!gates[v] && !expected_active[v];
            end
        end
        if(request && rst_n && gates==15 &&
           (active_instrument[0] || active_instrument[1] || active_instrument[2] || active_instrument[3]) &&
           !(active_instrument[0] && active_instrument[1] && active_instrument[2] && active_instrument[3])) mixed_colors++;
        #1;
        if($signed(sample)!==expected_sample || valid!==expected_valid || clipped!==expected_clip ||
           active!==expected_active || released!==expected_released || sounding!==( |expected_active))
            $fatal(1,"instrument case=%0d clock=%0d sample=%0d/%0d valid=%b/%b active=%b/%b done=%b/%b",
                   CASE_ID,clocks,$signed(sample),expected_sample,valid,expected_valid,
                   active,expected_active,released,expected_released);
        for(v=0;v<4;v++)
            begin
                if(levels[v*17 +: 17]!==level[v]) $fatal(1,"case=%0d clock=%0d voice=%0d envelope actual=%0d expected=%0d",CASE_ID,clocks,v,levels[v*17 +: 17],level[v]);
                if(tones[v*17 +: 17]!==tone_level[v]) $fatal(1,"case=%0d clock=%0d voice=%0d brightness actual=%0d expected=%0d",CASE_ID,clocks,v,tones[v*17 +: 17],tone_level[v]);
            end
        for(v=0;v<4;v++)
            if(observed_instrument[v]!==active_instrument[v])
                $fatal(1,"case=%0d clock=%0d voice=%0d instrument adoption actual=%b expected=%b",CASE_ID,clocks,v,observed_instrument[v],active_instrument[v]);
        if(dut.gain_valid!=={4{mix_ready}}) $fatal(1,"voice valid lanes differ");
        if(fd) $fdisplay(fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
            rst_n,request,gates,triggers,notes,velocities,instruments,$signed(sample),valid,clipped,
            active,released,sounding,levels[16:0],levels[33:17],levels[50:34],levels[67:51],observed_instrument,tones[16:0],tones[33:17],tones[50:34],tones[67:51]);
        clocks++;
        if(valid) begin
            samples++; if(sample>0) positive++; if(sample<0) negative++; if(clipped) begin clips++; if(sample==32767) positive_clip++; if(sample==-32768) negative_clip++; end
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
        if((CASE_ID==0 && $value$plusargs("INSTRUMENT_TRACE_SHORT=%s",trace_path)) ||
           (CASE_ID==1 && $value$plusargs("INSTRUMENT_TRACE_BOUNDARY=%s",trace_path)) ||
           (CASE_ID==2 && $value$plusargs("INSTRUMENT_TRACE_ZERO=%s",trace_path)) ||
           (CASE_ID==3 && $value$plusargs("INSTRUMENT_TRACE_EXTREME=%s",trace_path))) begin
            fd=$fopen(trace_path,"w");
            if(!fd) $fatal(1,"cannot open instrument trace");
            $fdisplay(fd,"# instrument_bank v1 GA=%0d GD=%0d GS=%0d GR=%0d SA=%0d SD=%0d SS=%0d SR=%0d GT=%0d ST=%0d SHIFT=%0d",GA,GD,GS,GR,SA,SD,SS,SR,GT,ST,SHIFT);
        end
        cycle(0,1,15,15); // 同时复位、请求、触发，必须全部清除。
        notes={7'd72,7'd67,7'd64,7'd60}; // 复位期间明确改变输入，兼容事件仿真初始化。
        repeat(5) tick(0,0);
        instruments=4'b1010;
        repeat(100) tick(15,0); // 四声部同时采用拨弦/弦乐/拨弦/弦乐。
        instruments=4'b0101;
        repeat(80) tick(15,0); // 保持键时变更选择，不改变现有乐器预设。
        repeat(4) tick(0,0);   // 正在释放时改变选择，同样保留尾音乐器预设。
        instruments=4'b1111;
        repeat(RN+5) tick(0,0);
        instruments=4'b1010; tick(15,0); // 起音中提前释放，S=0 也有非零尾音。
        instruments=4'b0101; repeat(RN+3) tick(0,0);
        instruments=4'b0101;
        repeat(80) tick(15,0); // 全部回收后的自然起音采用新乐器预设。
        instruments=4'b1010;
        tick(15,15); // 相同音符保持期间，明确 retrigger 才更换乐器预设。
        repeat(50) tick(15,0);

        // 暂存脉冲当拍的乐器预设，随后选择输入改变也不能污染它。
        instruments=4'b0101; cycle(1,0,15,15);
        instruments=4'b1010; cycle(1,0,15,0);
        tick(15,0); repeat(40) tick(15,0);
        // 同一采样间隔多个脉冲合并，最近脉冲的乐器预设获胜。
        instruments=4'b0000; cycle(1,0,15,15);
        instruments=4'b1111; cycle(1,0,15,15);
        instruments=4'b0000; tick(15,0); repeat(40) tick(15,0);
        // 采样当拍的新脉冲优先于此前暂存的脉冲。
        instruments=4'b1111; cycle(1,0,15,15);
        instruments=4'b0000; tick(15,15); repeat(40) tick(15,0);

        // 非采样拍的 gate=0 不得丢弃 pending；采样到 gate=0 才丢弃。
        instruments=4'b1111; cycle(1,0,0,15);
        instruments=4'b0000; cycle(1,0,15,0);
        tick(15,0); repeat(40) tick(15,0);
        instruments=4'b0000; cycle(1,0,15,15);
        instruments=4'b1111; tick(0,0);
        repeat(RN+4) tick(0,0);
        instruments=4'b1010; tick(15,0); repeat(50) tick(15,0);

        notes[13:7]=7'd76; instruments[1]=~instruments[1];
        tick(15,2); repeat(60) tick(15,0); // 第五音模拟：替换仍保持的槽 1。
        // 全音符范围包含阈值两侧（102/103）和最高音符 127。
        notes={7'd127,7'd103,7'd102,7'd69}; instruments=15;
        tick(15,15); repeat(300) tick(15,0);
        // 请求后立即改变输入；已有样本仍使用原乐器预设和力度快照。
        cycle(1,1,15,0); instruments=0; velocities=0;
        repeat(5) cycle(1,0,15,0);
        for(i=0;i<500;i++) begin
            instruments=i[3:0];
            velocities=(i[0])?{4{7'd127}}:{7'd0,7'd1,7'd64,7'd126};
            notes={7'd127,7'd103,7'd102,7'd60};
            cycle(1,1,15,(i%31==0)?4'b0101:4'b0000);
        end
        // 同相满幅检查饱和；两类符号都应出现。
        cycle(0,1,15,15); notes={4{7'd69}}; velocities={4{7'd127}}; instruments=0;
        repeat(500) tick(15,0);
        instruments=15; cycle(1,0,15,15);
        cycle(0,0,15,0); // reset 清除未消费的触发与乐器预设快照。
        instruments=0; repeat(50) tick(15,0);
        for(i=0;i<5000;i++) begin
            random_state=random_state*32'd1664525+32'd1013904223;
            notes=random_state[27:0];
            velocities=(random_state^32'h7263bc19)&28'hfffffff;
            instruments=random_state[7:4];
            cycle(i%997!=0,random_state[31],random_state[27:24],random_state[23:20]);
        end
        repeat(RN+8) tick(0,0);
        repeat(20) tick(0,0); // 长空闲仍维持静音、释放完成和正确 valid。
        repeat(5) cycle(1,0,0,0);
        // 极大时长只验证有限前缀；明确复位清空长尾，不声称等待完成2^31拍。
        if(CASE_ID==3) begin
            cycle(0,1,15,15);
            instruments=0; notes={4{7'd69}}; velocities={4{7'd127}};
            repeat(5) tick(15,0); // G起音1拍后保持UNITY。
            instruments=15; tick(15,15);
            repeat(100) tick(15,0); // S从当前UNITY重起，巨大Attack不能提前结束。
            if(levels!=={4{17'd65536}}) $fatal(1,"huge attack lost start level");
            repeat(100) tick(0,0); // 巨大release前100拍floor步长为0，仍保持UNITY。
            if(levels!=={4{17'd65536}} || active!==15 || released!==0)
                $fatal(1,"huge release ended early");
            cycle(0,0,0,0); repeat(5) cycle(1,0,0,0);
        end
        if(sample!==0 || released!==15 || active!==0 || levels!==0) $fatal(1,"final release not silent");
        if(samples<2000 || positive==0 || negative==0 || resets<4) $fatal(1,"incomplete instrument coverage");
        if(SHIFT==0 && (positive_clip==0 || negative_clip==0)) $fatal(1,"missing both saturation signs");
        if(CASE_ID==2 && zero_held==0) $fatal(1,"missing zero sustain held preset retention");
        if(SHIFT==5 && clips!=0) $fatal(1,"quiet output clipped");
        if(accepted_guitar==0 || accepted_strings==0 || deferred==0 || replaced==0 || override_now==0 ||
           held_ignored==0 || tail_ignored==0 || fallback==0 || mixed_colors==0 || discarded==0)
            $fatal(1,"missing instrument adoption/fallback coverage");
        $display("instrument coverage guitar=%0d strings=%0d deferred=%0d replaced=%0d override=%0d held=%0d tail=%0d fallback=%0d mixed=%0d discarded=%0d",
                 accepted_guitar,accepted_strings,deferred,replaced,override_now,held_ignored,tail_ignored,fallback,mixed_colors,discarded);
        if(fd) begin
            $fdisplay(fd,"# completed clocks=%0d samples=%0d resets=%0d",clocks,samples,resets);
            $fclose(fd);
        end
        $display("instrument case=%0d verified %0d clocks, %0d samples, %0d resets, %0d clips",
                 CASE_ID,clocks,samples,resets,clips);
        done=1;
    end
endmodule

module tb_instrument_bank;
    wire default_done, boundary_done, zero_done, extreme_done;
    instrument_bank_case default_case(default_done);
    instrument_bank_case #(.CASE_ID(1),.GA(0),.GD(1),.GS(70000),.GR(1),
        .SA(1),.SD(0),.SS(65536),.SR(0),.GT(0),.ST(1),.SHIFT(0))
        boundary_case(boundary_done);
    instrument_bank_case #(.CASE_ID(2),.SS(0)) zero_case(zero_done);
    instrument_bank_case #(.CASE_ID(3),.GA(0),.GD(1),.GS(65536),.GR(0),
        .SA(32'h80000000),.SD(32'hffffffff),.SS(70000),.SR(32'h80000000),
        .GT(32'hffffffff),.ST(1)) extreme_case(extreme_done);
    initial begin
        wait(default_done && boundary_done && zero_done && extreme_done);
        #3; $display("PASS: tb_instrument_bank mixed voices, per-note instrument snapshots, pending triggers, high-note fallback and R4 pipeline.");
        $finish;
    end
    initial begin #50000000; $fatal(1,"instrument bank timeout"); end
endmodule
