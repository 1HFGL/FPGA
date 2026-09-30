`timescale 1ns/1ps
module tb_adsr_env;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, sample_tick = 0, gate = 0, retrigger = 0;
    wire [16:0] env_level, instant_level, clamped_level;
    wire active;
    wire [2:0] state;
    integer checks = 0;
    adsr_env #(.ATTACK_STEP(17'd20000), .DECAY_STEP(17'd10000),
               .SUSTAIN_LEVEL(17'd25000), .RELEASE_STEP(17'd12000)) dut (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .gate(gate),
        .retrigger(retrigger), .env_level(env_level), .active(active), .state(state)
    );
    adsr_env #(.ATTACK_STEP(17'd0), .DECAY_STEP(17'd0),
               .SUSTAIN_LEVEL(17'd0), .RELEASE_STEP(17'd0)) instant (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .gate(gate),
        .retrigger(retrigger), .env_level(instant_level), .active(), .state()
    );
    adsr_env #(.ATTACK_STEP(17'd131071), .DECAY_STEP(17'd131071),
               .SUSTAIN_LEVEL(17'd131071), .RELEASE_STEP(17'd131071)) clamped (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .gate(gate),
        .retrigger(retrigger), .env_level(clamped_level), .active(), .state()
    );

    task step;
        input r, tick, g, trig;
        input integer expected, expected_state;
        begin
            @(negedge clk);
            rst=r; sample_tick=tick; gate=g; retrigger=trig;
            @(posedge clk); #1;
            if (env_level !== expected || state !== expected_state ||
                active !== (expected_state != 0))
                $fatal(1, "ADSR check %0d: level=%0d state=%0d expected=%0d/%0d",
                       checks, env_level, state, expected, expected_state);
            if (instant_level > 65536 || clamped_level > 65536)
                $fatal(1, "Envelope out of range");
            checks=checks+1;
        end
    endtask

    initial begin
        // IDLE=0, ATTACK=1, DECAY=2, SUSTAIN=3, RELEASE=4.
        step(1,1,1,1,0,0); // reset wins over all inputs
        step(0,0,0,0,0,0);
        step(0,1,1,0,20000,1);
        if (instant_level !== 17'd65536 || clamped_level !== 17'd65536)
            $fatal(1, "Immediate/saturated attack failed");
        step(0,0,1,0,20000,1); // no tick: hold
        step(0,1,1,0,40000,1);
        if (instant_level !== 17'd0 || clamped_level !== 17'd65536)
            $fatal(1, "Zero-time decay or sustain clamp failed");
        step(0,1,1,0,60000,1);
        step(0,1,1,0,65536,2); // clamp; never wrap
        step(0,1,1,0,55536,2);
        step(0,1,1,0,45536,2);
        step(0,1,1,0,35536,2);
        step(0,1,1,0,25536,2);
        step(0,1,1,0,25000,3);
        repeat(5) step(0,1,1,0,25000,3);
        step(0,0,0,0,25000,3); // gate changes only affect audio ticks
        step(0,1,0,0,13000,4);
        if (instant_level !== 17'd0 || clamped_level !== 17'd0)
            $fatal(1, "Immediate/saturated release failed");
        step(0,1,0,0,1000,4);
        step(0,1,0,0,0,0);
        step(0,1,0,1,0,0); // low gate wins over retrigger

        step(0,1,1,0,20000,1);
        step(0,1,0,0,8000,4); // release during attack
        step(0,1,1,0,28000,1); // reattack from current level
        step(0,1,1,0,48000,1);
        step(0,1,1,0,65536,2);
        step(0,1,1,0,55536,2);
        step(0,0,1,1,55536,2); // one-clock retrigger between ticks
        step(0,0,1,0,55536,2);
        step(0,1,1,0,65536,2); // pending request consumed once
        step(0,1,1,0,55536,2);
        step(0,1,0,0,43536,4); // release during decay
        step(1,0,1,1,0,0); // reset during release, no audio tick
        step(0,1,1,0,20000,1);
        step(1,1,1,0,0,0); // reset during attack
        step(0,1,1,0,20000,1);
        step(0,1,1,0,40000,1);
        step(0,1,1,0,60000,1);
        step(0,1,1,0,65536,2);
        step(1,0,1,0,0,0); // reset during decay
        step(0,1,1,0,20000,1);
        step(0,1,1,0,40000,1);
        step(0,1,1,0,60000,1);
        step(0,1,1,0,65536,2);
        step(0,1,1,0,55536,2);
        step(0,1,1,0,45536,2);
        step(0,1,1,0,35536,2);
        step(0,1,1,0,25536,2);
        step(0,1,1,0,25000,3);
        step(0,1,1,1,45000,1); // sustain retrigger, no zero jump
        step(0,1,1,0,65000,1);
        step(0,1,1,0,65536,2);
        step(0,1,1,0,55536,2);
        step(0,1,1,0,45536,2);
        step(0,1,1,0,35536,2);
        step(0,1,1,0,25536,2);
        step(0,1,1,0,25000,3);
        step(1,0,1,0,0,0); // reset during sustain
        $display("PASS: adsr_env directed checks (%0d).", checks);
        $stop;
    end
    initial begin #100000; $fatal(1, "ADSR timeout"); end
endmodule
