`timescale 1ns/1ps
// 导出真实 RTL 样本，由 Python 整数参考检查相位、包络、符号和流水线。
module tb_demo_voice_bank;
    reg clk=0, rst_n=0, request=0;
    reg [3:0] gates=0;
    reg [27:0] notes={7'd127,7'd69,7'd64,7'd60};
    reg [27:0] velocities={7'd127,7'd100,7'd0,7'd127};
    wire [3:0] done;
    wire sounding, valid;
    wire signed [15:0] sample;
    integer fd, i, samples=0, positive=0, negative=0;
    demo_voice_bank dut(.clk(clk),.rst_n(rst_n),.sample_request(request),
        .voice_gate(gates),.voice_note_flat(notes),.voice_velocity_flat(velocities),
        .release_done(done),.sounding(sounding),.sample_data(sample),.sample_valid(valid));
    always #10 clk=~clk;
    task reset_bank;
        begin
            @(negedge clk); rst_n=0; request=0; gates=0;
            repeat(3) @(negedge clk);
            if (valid !== 0 || sample !== 0 || done !== 4'b1111 || sounding !== 0)
                begin $display("FAIL: bank reset failed"); $finish; end
            $fdisplay(fd,"reset");
            rst_n=1;
        end
    endtask
    task take_sample;
        begin
            @(negedge clk); request=1;
            @(posedge clk); #1;
            if(valid !== 0) begin $display("FAIL: early valid R0"); $finish; end
            @(negedge clk); request=0;
            @(posedge clk); #1;
            if(valid !== 0) begin $display("FAIL: early valid R1"); $finish; end
            @(posedge clk); #1;
            if(valid !== 1 || ^sample === 1'bx) begin $display("FAIL: missing/unknown R2 sample"); $finish; end
            if(sample > 4049 || sample < -4049) begin $display("FAIL: mix headroom overflow"); $finish; end
            $fdisplay(fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                gates[0],notes[6:0],velocities[6:0],
                gates[1],notes[13:7],velocities[13:7],
                gates[2],notes[20:14],velocities[20:14],
                gates[3],notes[27:21],velocities[27:21],$signed(sample));
            samples=samples+1;
            if(sample>0) positive=positive+1;
            if(sample<0) negative=negative+1;
            repeat(5) begin
                @(posedge clk); #1;
                if(valid !== 0) begin $display("FAIL: valid longer than one clock"); $finish; end
            end
        end
    endtask
    initial begin
        fd=$fopen("results/logs/abc_mix_trace.txt","w");
        if(!fd) begin $display("FAIL: cannot open mix trace"); $finish; end
        reset_bank();
        repeat(5) take_sample();
        gates=4'b1111;
        repeat(400) take_sample();
        // 运行中换音与边界力度：零力度声部不得贡献样本。
        notes={7'd36,7'd37,7'd38,7'd39};
        velocities={7'd127,7'd127,7'd127,7'd127};
        repeat(160) take_sample();
        gates=0;
        if(done !== 0) begin $display("FAIL: release completed before envelope tail"); $finish; end
        repeat(70) take_sample();
        if(done !== 4'b1111 || sample !== 0 || sounding !== 0) begin $display("FAIL: release stuck"); $finish; end
        gates=1;
        repeat(40) take_sample();
        reset_bank(); // 发声中复位，再触发并检查独立相位从零开始。
        gates=4'b1010;
        repeat(70) take_sample();
        if(samples!=745 || positive==0 || negative==0) begin $display("FAIL: incomplete bank test"); $finish; end
        $fclose(fd);
        $display("PASS tb_demo_voice_bank: 745 samples, latency, velocity, release, reset");
        $finish;
    end
    initial begin #1000000; begin $display("FAIL: bank timeout"); $finish; end end
endmodule
