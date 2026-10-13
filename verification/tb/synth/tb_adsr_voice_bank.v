`timescale 1ns/1ps
// 用真实默认采样点数验证四个独立包络，时钟请求加速，不冒称实物时长。
module tb_adsr_voice_bank;
    reg clk=0, rst_n=0, request=0;
    reg [3:0] gates=0, triggers=0, trace_trigger=0;
    reg [27:0] notes={7'd127,7'd69,7'd64,7'd60};
    reg [27:0] velocities={7'd127,7'd100,7'd0,7'd127};
    wire [3:0] done;
    wire [67:0] levels;
    wire sounding, valid;
    wire signed [15:0] sample;
    integer fd, count=0, positive=0, negative=0, v;
    adsr_voice_bank dut(.clk(clk), .rst_n(rst_n), .sample_request(request),
        .voice_gate(gates), .voice_trigger(triggers), .voice_note_flat(notes),
        .voice_velocity_flat(velocities), .release_done(done), .sounding(sounding),
        .sample_data(sample), .sample_valid(valid), .env_level_flat(levels));
    always #10 clk=~clk;
    task reset_bank;
        begin
            @(negedge clk); rst_n=0; request=0; gates=0; triggers=0; trace_trigger=0;
            repeat(3) @(negedge clk);
            if(valid!==0 || sample!==0 || done!==15 || sounding!==0 || levels!==0)
                begin $display("FAIL: ADSR bank reset failed"); $finish; end
            $fdisplay(fd,"reset");
            rst_n=1;
        end
    endtask
    task take_sample;
        begin
            @(negedge clk); request=1;
            @(posedge clk); #1;
            if(valid!==0) begin $display("FAIL: ADSR early valid R0"); $finish; end
            @(negedge clk); request=0; triggers=0;
            repeat(2) begin
                @(posedge clk); #1;
                if(valid!==0) begin $display("FAIL: ADSR early valid R1/R2"); $finish; end
            end
            @(posedge clk); #1;
            if(valid!==1 || ^sample===1'bx) begin $display("FAIL: ADSR missing R3 output"); $finish; end
            if(sample < -4064 || sample > 4063) begin $display("FAIL: ADSR mix overflow"); $finish; end
            for(v=0; v<4; v=v+1) begin
                if(levels[v*17+:17]!=0 && !gates[v] && done[v])
                    begin $display("FAIL: premature release voice %0d",v); $finish; end
                $fwrite(fd,"%0d %0d %0d %0d %0d ", gates[v],trace_trigger[v],
                    notes[v*7+:7],velocities[v*7+:7],levels[v*17+:17]);
            end
            $fdisplay(fd,"%0d %0d %0d",$signed(sample),done,sounding);
            count=count+1;
            positive=positive+(sample>0); negative=negative+(sample<0);
            trace_trigger=0;
            repeat(4) begin
                @(posedge clk); #1;
                if(valid!==0) begin $display("FAIL: ADSR duplicate valid"); $finish; end
            end
        end
    endtask
    task pulse_between_samples;
        begin
            @(negedge clk); triggers=4'b0001; trace_trigger=4'b0001;
            @(negedge clk); triggers=0;
        end
    endtask
    initial begin
        fd=$fopen("build/regression/logs/adsr_mix_trace.txt","w");
        if(!fd) begin $display("FAIL: cannot create ADSR mix trace"); $finish; end
        reset_bank();
        repeat(5) take_sample();
        gates=15;
        repeat(96) take_sample();
        if(levels!=={4{17'd65536}}) begin $display("FAIL: attack endpoint/time"); $finish; end
        // 不同声部在不同阶段松键，后续由独立Python直线模型核对。
        gates=4'b1110;
        repeat(1000) take_sample();
        gates=4'b1100;
        repeat(5000) take_sample();
        if(!done[0] || done[1]) begin $display("FAIL: independent release timing"); $finish; end
        gates=4'b1110; // 释放过程中重按声部1。
        repeat(100) take_sample();
        repeat(19000) take_sample();
        if(levels[3*17+:17]!==6554) begin $display("FAIL: decay/sustain endpoint"); $finish; end
        // gate 不变且音符不变的单拍重触发必须被暂存。
        gates=15; repeat(100) take_sample();
        repeat(24000) take_sample();
        pulse_between_samples();
        take_sample();
        if(levels[0+:17]<=6554) begin $display("FAIL: pending retrigger lost"); $finish; end
        repeat(95) take_sample();
        if(levels[0+:17]!==65536) begin $display("FAIL: retrigger attack duration"); $finish; end
        notes={7'd36,7'd37,7'd38,7'd39}; velocities={4{7'd127}};
        repeat(100) take_sample();
        gates=0;
        repeat(5759) take_sample();
        if(done!==0) begin $display("FAIL: release shorter than 5760 samples"); $finish; end
        take_sample();
        if(done!==15 || sample!==0 || sounding!==0) begin $display("FAIL: release did not complete"); $finish; end
        gates=1; repeat(30) take_sample();
        reset_bank(); // 活动包络中复位，然后检查相位也回零。
        gates=10; repeat(50) take_sample();
        gates=0; repeat(5760) take_sample();
        if(done!==15 || sample!==0 || sounding!==0 || !positive || !negative)
            begin $display("FAIL: incomplete ADSR bank coverage"); $finish; end
        $fclose(fd);
        $display("PASS tb_adsr_voice_bank: %0d samples; stages, four voices, signed mix, retrigger, reset",count);
        $finish;
    end
    initial begin #30000000; begin $display("FAIL: ADSR bank timeout"); $finish; end end
endmodule
