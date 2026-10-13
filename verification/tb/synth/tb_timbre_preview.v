`timescale 1ns/1ps
// 只导出真实 RTL 样本。后续 Python 必须独立逐样本核对后才能生成试听 WAV。
// 每片段48k样本，播放时为1秒；仿真加速到每4个clk请求一次。
module tb_timbre_preview;
    reg clk=0, rst_n=0, request=0;
    reg [3:0] gate=0, timbres=0;
    wire [3:0] done_voice, active;
    wire [67:0] env;
    wire sounding, valid, clipped;
    wire signed [15:0] sample;
    reg [2047:0] path;
    integer fd=0, tone=0, written=0, n;
    always #10 clk=~clk;
    voice_bank_adsr dut (
        .clk(clk),.rst_n(rst_n),.sample_request(request),
        .voice_gate(gate),.voice_retrigger(4'b0),.voice_timbre(timbres),
        .voice_note_flat({4{7'd69}}),.voice_velocity_flat({4{7'd127}}),
        .release_done(done_voice),.voice_active(active),.env_level_flat(env),
        .sounding(sounding),.sample_data(sample),.sample_valid(valid),.sample_clipped(clipped));
    always @(posedge clk) begin
        #1;
        if(valid) begin
            if(!fd || clipped) begin $display("FAIL: preview file missing or clipping"); $finish; end
            $fdisplay(fd,"%0d,69,%0d,%0d",tone,written,$signed(sample));
            written=written+1;
        end
    end
    initial begin
        if(!$value$plusargs("TIMBRE_PREVIEW=%s",path)) begin $display("FAIL: TIMBRE_PREVIEW path required"); $finish; end
        fd=$fopen(path,"w");
        if(!fd) begin $display("FAIL: cannot open preview CSV"); $finish; end
        $fdisplay(fd,"timbre,note,index,sample");
        for(tone=0;tone<2;tone=tone+1) begin
            @(negedge clk); rst_n=0; request=0; gate=0; timbres=tone;
            repeat(3) @(negedge clk);
            rst_n=1; written=0;
            for(n=0;n<48000;n=n+1) begin
                @(negedge clk); request=1; gate=(n<36000)?4'b0001:4'b0000;
                @(negedge clk); request=0;
                repeat(2) @(negedge clk);
            end
            repeat(4) @(negedge clk);
            if(written!=48000 || sample!==0 || active!==0 || done_voice!==15)
                begin $display("FAIL: preview incomplete: tone=%0d count=%0d",tone,written); $finish; end
        end
        $fclose(fd); fd=0;
        $display("PASS: two RTL timbre preview segments, 48000 samples each, tails silent.");
        $finish;
    end
endmodule
