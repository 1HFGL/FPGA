`timescale 1ns/1ps
// 钢琴分支必须逐样本等于原钢琴（仅多一拍）；另查吉他选择与旧音色锁存。
module tb_review_dual_voice;
    reg clk=0,rst=1,tick=0,gate=0,retrigger=0,mode=0;
    wire signed [15:0] original_sample,dual_sample;
    wire original_valid,dual_valid;
    wire [16:0] original_env,dual_env;
    reg previous_valid=0,compare_piano=1;
    reg signed [15:0] previous_sample=0;
    integer checks=0,differences=0;
    always #10 clk=~clk;
    voice_timbre_adsr #(.ROM_FILE("rtl/rom/piano_1024.mem"),.BRIGHT_ROM_FILE("rtl/rom/piano_1024.mem"),
        .ATTACK_SAMPLES(4),.DECAY_SAMPLES(12),.SUSTAIN_LEVEL(32768),.RELEASE_SAMPLES(5)) original(
        .clk(clk),.rst(rst),.sample_tick(tick),.phase_inc(32'd23409859),.gate(gate),.retrigger(retrigger),.timbre(1'b0),
        .sample(original_sample),.sample_valid(original_valid),.env_level(original_env),.voice_active());
    voice_timbre_adsr #(.ROM_FILE("rtl/rom/piano_1024.mem"),.ENABLE_GUITAR(1),
        .ATTACK_SAMPLES(4),.DECAY_SAMPLES(12),.SUSTAIN_LEVEL(32768),.RELEASE_SAMPLES(5)) dual(
        .clk(clk),.rst(rst),.sample_tick(tick),.phase_inc(32'd23409859),.gate(gate),.retrigger(retrigger),.timbre(mode),
        .sample(dual_sample),.sample_valid(dual_valid),.env_level(dual_env),.voice_active());
    always @(posedge clk)begin
        #1;
        if(rst)begin previous_valid=0;previous_sample=0;end
        else begin
            if(dual_valid!==previous_valid)begin $display("FAIL dual voice valid alignment");$finish;end
            if(compare_piano)begin
                if(dual_env!==original_env || (dual_valid && dual_sample!==previous_sample))begin
                    $display("FAIL dual piano changed env=%0d/%0d sample=%0d/%0d",dual_env,original_env,dual_sample,previous_sample);$finish;
                end
                if(dual_valid)checks=checks+1;
            end else if(dual_valid && dual_sample!=previous_sample)differences=differences+1;
            previous_valid=original_valid;previous_sample=original_sample;
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst=0;tick=1;gate=1;retrigger=1;
        @(negedge clk);retrigger=0;repeat(40)@(negedge clk);
        mode=1;repeat(30)@(negedge clk); // 切模式不能改变原钢琴持续音。
        if(dual.g_dual.u_instrument.active_instrument!==1)begin $display("FAIL old piano changed timbre");$finish;end
        gate=0;repeat(10)@(negedge clk);
        compare_piano=0;gate=1;retrigger=1;
        @(negedge clk);retrigger=0;repeat(130)@(negedge clk);
        if(dual.g_dual.u_instrument.active_instrument!==0 ||
           dual.g_dual.u_instrument.tone_level>=65536 || differences<20)begin
            $display("FAIL guitar preset/brightness not active");$finish;
        end
        rst=1;repeat(4)@(negedge clk);
        if(dual_sample!==0 || dual_valid!==0)begin $display("FAIL dual voice reset");$finish;end
        if(checks<60)begin $display("FAIL dual voice insufficient reference checks");$finish;end
        $display("PASS tb_review_dual_voice: exact piano samples, one-cycle alignment, locked old timbre, guitar brightness and reset");$finish;
    end
    initial begin #100000;$display("FAIL dual voice timeout");$finish;end
endmodule
