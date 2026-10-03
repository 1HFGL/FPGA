`timescale 1ns/1ps

// 各组参数并行验证；default_case 的信号保留给 ModelSim 波形脚本。
module tb_adsr_env;
    reg clk=0;
    always #5 clk=~clk;
    wire rst, sample_tick, gate, retrigger, active;
    wire [16:0] env_level;
    wire [2:0] state;
    wire [9:0] done;
    wire [31:0] c0,c1,c2,c3,c4,c5,c6,c7,c8,c9;
    adsr_duration_case default_case (.clk(clk),.done(done[0]),.checks(c0),
        .rst(rst),.sample_tick(sample_tick),.gate(gate),.retrigger(retrigger),
        .env_level(env_level),.active(active),.state(state));
    adsr_duration_case #(.A(7),.D(11),.S(25000),.R(13)) coprime (
        .clk(clk),.done(done[1]),.checks(c1),.rst(),.sample_tick(),
        .gate(),.retrigger(),.env_level(),.active(),.state());
    adsr_duration_case #(.A(0),.D(0),.S(0),.R(0)) zero_time (
        .clk(clk),.done(done[2]),.checks(c2),.rst(),.sample_tick(),
        .gate(),.retrigger(),.env_level(),.active(),.state());
    adsr_duration_case #(.A(1),.D(1),.S(65536),.R(1)) one_tick (
        .clk(clk),.done(done[3]),.checks(c3),.rst(),.sample_tick(),
        .gate(),.retrigger(),.env_level(),.active(),.state());
    // 时长大于幅度分辨率，且从幅度 1 释放：不能因步长取整而卡住或提前结束。
    adsr_duration_case #(.A(17),.D(65537),.S(1),.R(70001)) tiny_release (
        .clk(clk),.done(done[4]),.checks(c4),.rst(),.sample_tick(),
        .gate(),.retrigger(),.env_level(),.active(),.state());
    adsr_duration_case #(.A(65537),.D(3),.S(0),.R(5)) slow_attack (
        .clk(clk),.done(done[5]),.checks(c5),.rst(),.sample_tick(),
        .gate(),.retrigger(),.env_level(),.active(),.state());
    adsr_duration_case #(.A(3),.D(4),.S(131071),.R(7)) sustain_clamp (
        .clk(clk),.done(done[6]),.checks(c6),.rst(),.sample_tick(),
        .gate(),.retrigger(),.env_level(),.active(),.state());
    // N 是 2 的幂时计数器必须多保留一位；完整阶段不能提前结束。
    adsr_duration_case #(.A(256),.D(512),.S(16384),.R(1024)) power_of_two (
        .clk(clk),.done(done[7]),.checks(c7),.rst(),.sample_tick(),
        .gate(),.retrigger(),.env_level(),.active(),.state());
    // 完整跑完 2^32 点不现实；检查开头 70000 点，跨越误差加法的进位。
    adsr_wide_case wide_decay (.clk(clk),.done(done[8]),.checks(c8));
    adsr_wide_case #(.A(32'hffffffff),.R(32'hffffffff)) wide_attack (
        .clk(clk),.done(done[9]),.checks(c9));
    initial begin
        wait (&done);
        $display("PASS: adsr_env duration checks (%0d checks, 10 parameter sets).",
                 c0+c1+c2+c3+c4+c5+c6+c7+c8+c9);
        $stop;
    end
    initial begin #100000000; $fatal(1,"ADSR duration timeout"); end
endmodule

// 32 位无符号时长边界。参考模型直接计算直线，独立于 RTL 的计数/余数。
module adsr_wide_case #(
    parameter [31:0] A=32'd1, D=32'hffffffff, R=32'h80000000
) (
    input wire clk,
    output reg done=0,
    output reg [31:0] checks=0
);
    reg rst=1, sample_tick=0, gate=0, retrigger=0;
    wire [16:0] env_level;
    wire [2:0] state;
    wire active;
    integer k, expected, saved_level;
    adsr_env #(.ATTACK_SAMPLES(A),.DECAY_SAMPLES(D),
               .SUSTAIN_LEVEL(17'd1),.RELEASE_SAMPLES(R)) dut (
        .clk(clk),.rst(rst),.sample_tick(sample_tick),.gate(gate),
        .retrigger(retrigger),.env_level(env_level),.active(active),.state(state));

    function integer line_level;
        input integer start_level, end_level, age;
        input [31:0] duration;
        reg [63:0] product;
        begin
            if (end_level>=start_level) begin
                product=end_level-start_level;
                product=product*age;
                line_level=start_level+product/duration;
            end else begin
                product=start_level-end_level;
                product=product*age;
                line_level=start_level-product/duration;
            end
        end
    endfunction

    task step;
        input r,t,g,trig;
        input integer level_value,state_value;
        begin
            @(negedge clk);
            rst=r; sample_tick=t; gate=g; retrigger=trig;
            @(posedge clk); #1;
            if (env_level!==level_value || state!==state_value ||
                active!==(state_value!=0))
                $fatal(1,"Wide ADSR A=%h D=%h R=%h check=%0d got %0d/%0d expected %0d/%0d",
                    A,D,R,checks,env_level,state,level_value,state_value);
            checks=checks+1;
        end
    endtask

    initial begin
        step(1,0,1,1,0,0);
        for(k=1;k<=70000;k=k+1) begin
            if (A==1) begin
                expected=(k==1)?65536:line_level(65536,1,k-1,D);
                step(0,1,1,0,expected,2);
            end else begin
                expected=line_level(0,65536,k,A);
                step(0,1,1,0,expected,1);
            end
        end
        saved_level=expected;
        for(k=1;k<=70000;k=k+1) begin
            expected=line_level(saved_level,0,k,R);
            step(0,1,0,1,expected,4); // 松键仍优先于触发，释放不能重启
        end
        step(0,0,1,1,expected,4);
        saved_level=expected;
        expected=line_level(saved_level,65536,1,A);
        step(0,1,1,0,expected,(A==1)?2:1);
        step(1,0,0,0,0,0);
        @(negedge clk); sample_tick=0; retrigger=0; done=1;
    end
endmodule

module adsr_duration_case #(
    parameter integer A=96, D=24000, S=6554, R=5760
) (
    input wire clk,
    output reg done=0,
    output reg [31:0] checks=0,
    output reg rst=1, sample_tick=0, gate=0, retrigger=0,
    output wire [16:0] env_level,
    output wire active,
    output wire [2:0] state
);
    localparam integer AN=(A==0)?1:A, DN=(D==0)?1:D, RN=(R==0)?1:R;
    localparam integer SN=(S>65536)?65536:S;
    integer expected=0, expected_state=0, part;
    adsr_env #(.ATTACK_SAMPLES(A),.DECAY_SAMPLES(D),
               .SUSTAIN_LEVEL(S),.RELEASE_SAMPLES(R)) dut (
        .clk(clk),.rst(rst),.sample_tick(sample_tick),.gate(gate),
        .retrigger(retrigger),.env_level(env_level),.active(active),.state(state));

    // 参考值用“起点 + 总距离 * 已走步数 / 总步数”直接计算。
    // 乘积用 64 位，独立于 RTL 的余数累加算法；长时长测试不能溢出。
    function integer line_level;
        input integer start_level, end_level, age, duration;
        reg [63:0] product;
        begin
            if (end_level>=start_level) begin
                product=end_level-start_level;
                product=product*age;
                line_level=start_level+product/duration;
            end else begin
                product=start_level-end_level;
                product=product*age;
                line_level=start_level-product/duration;
            end
        end
    endfunction

    task step;
        input r,t,g,trig;
        input integer level_value,state_value;
        begin
            @(negedge clk);
            rst=r; sample_tick=t; gate=g; retrigger=trig;
            @(posedge clk); #1;
            if (env_level!==level_value || state!==state_value ||
                active!==(state_value!=0))
                $fatal(1,"ADSR A=%0d D=%0d S=%0d R=%0d check=%0d: got %0d/%0d expected %0d/%0d",
                    A,D,S,R,checks,env_level,state,level_value,state_value);
            expected=level_value; expected_state=state_value;
            checks=checks+1;
        end
    endtask

    task reset_env;
        begin step(1,0,1,1,0,0); end // 复位不依赖 sample_tick，也清掉待处理触发
    endtask

    task attack;
        input integer start_level, count;
        input first_trigger;
        integer k;
        begin
            for(k=1;k<=count;k=k+1) begin
                step(0,1,1,(k==1)&&first_trigger,
                     line_level(start_level,65536,k,AN),(k==AN)?2:1);
                if(k==1) repeat(2) step(0,0,1,0,expected,expected_state);
            end
        end
    endtask

    task decay;
        input integer count;
        integer k;
        begin
            for(k=1;k<=count;k=k+1)
                step(0,1,1,0,line_level(65536,SN,k,DN),(k==DN)?3:2);
        end
    endtask

    task release_env;
        input integer start_level, count;
        integer k;
        begin
            if(start_level==0) step(0,1,0,1,0,0);
            else for(k=1;k<=count;k=k+1) begin
                // 故意同时拉高 retrigger：松键必须优先，释放不能每拍重启。
                step(0,1,0,1,line_level(start_level,0,k,RN),(k==RN)?0:4);
                if(k==1) repeat(2) step(0,0,0,0,expected,expected_state);
            end
        end
    endtask

    initial begin
        step(1,1,1,1,0,0);
        step(0,0,0,0,0,0);
        // 完整 A/D/S/R：保持阶段不自动结束，松键后精确 RN 点归零。
        attack(0,AN,0); decay(DN);
        repeat(5) step(0,1,1,0,SN,3);
        step(0,0,0,0,SN,3); // gate 改变但没有采样，包络应保持
        release_env(SN,RN);
        step(0,1,0,1,0,0);

        // 提前松键：从起音中间、衰减中间释放，都使用完整 RN 点。
        part=(AN/3<1)?1:AN/3;
        attack(0,part,0);
        release_env(expected,RN);
        attack(0,AN,0);
        part=(DN/3<1)?1:DN/3;
        decay(part);
        release_env(expected,RN);

        // 释放中重新按下：从当前值开始，不能清零，也不能继续旧倒计时。
        attack(0,AN,0);
        release_env(65536,1);
        attack(expected,AN,0); decay(DN);
        // 单 clk 脉冲发生在两次采样之间，应只消费一次。
        step(0,0,1,1,SN,3);
        step(0,0,1,0,SN,3);
        attack(SN,AN,0);
        decay(1);
        attack(expected,AN,1); // 衰减期间直接重触发
        decay(DN);
        attack(SN,AN,1); // 保持期间直接重触发
        decay(DN);

        // 各阶段同步复位，以及复位对待处理触发的清除。
        reset_env(); attack(0,1,0); reset_env();
        attack(0,AN,0); reset_env();
        attack(0,AN,0); decay(DN); reset_env();
        attack(0,AN,0); release_env(65536,1); reset_env();
        step(0,0,1,1,0,0);
        reset_env();
        step(0,1,0,0,0,0);
        attack(0,AN,0); decay(DN);
        release_env(SN,RN);
        @(negedge clk); sample_tick=0; retrigger=0; done=1;
    end
endmodule
