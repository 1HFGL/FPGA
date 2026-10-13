`timescale 1ns/1ps
// 编译期参数拒绝测试。非法配置必须由被测RTL在time0明确拒绝，
// 不能把测试平台自己的超时或缺少PASS误判为guard有效。
module tb_audio_parameters;
    parameter integer CASE_ID=0;
    localparam integer LEAD=(CASE_ID==2)?64:(CASE_ID==3)?-1:
        ((CASE_ID==1 || CASE_ID==9 || CASE_ID==10 || CASE_ID==14)?2:0);
    localparam integer CLOCK_HZ=(CASE_ID==4)?0:(CASE_ID==9)?6144000:
        (CASE_ID==10)?4608000:(CASE_ID==14)?7680000:50000000;
    // 67108865*64=4294967360，若错误地先用32位计算会回绕为64。
    localparam integer RATE_HZ=(CASE_ID==5)?0:(CASE_ID==6)?67108865:48000;
    localparam integer SLOT=(CASE_ID==7)?0:(CASE_ID==8)?16385:(CASE_ID==11)?-1:16;
    localparam integer LATENCY=(CASE_ID==12)?0:4;
    localparam integer SAMPLE=(CASE_ID==13)?8:16;
    localparam integer LEGAL=(CASE_ID==0 || CASE_ID==1 || CASE_ID==14);
    reg clk=0,rst=0;
    reg [3:0] response_pipe=0;
    wire ready,request,frame_start,underrun;
    integer requests=0,frames=0;
    always #10 clk=~clk;
    generate
        if(CASE_ID==7 || CASE_ID==8 || CASE_ID==11) begin: g_tick_only
            // 单独检查tick的16位边沿索引边界，不让synth_top格式检查代替它。
            sample_tick #(.AUDIO_CLK_HZ(CLOCK_HZ),.SAMPLE_RATE_HZ(RATE_HZ),
                .SLOT_BITS(SLOT),.REQUEST_LEAD_HALF_EDGES(LEAD)) dut(
                .clk_audio(clk),.rst_n(rst),.bclk_half_ce(),
                .frame_start(frame_start),.sample_prepare(request));
            assign ready=rst;
            assign underrun=1'b0;
        end else begin: g_synth
            synth_top #(.AUDIO_CLK_HZ(CLOCK_HZ),.SAMPLE_RATE_HZ(RATE_HZ),
                .SAMPLE_BITS(SAMPLE),.SLOT_BITS(SLOT),.REQUEST_LEAD_HALF_EDGES(LEAD),
                .MAX_SAMPLE_LATENCY_CYCLES(LATENCY)) dut(
                .clk_in(clk),.rst_n(rst),.audio_enable(1'b1),
                .sample_data({SAMPLE{1'b0}}),.sample_valid(response_pipe[3]),
                .audio_ready(ready),.sample_request(request),.sample_underrun(underrun),
                .i2s_bclk(),.i2s_lrclk(),.i2s_sdata(),.pa_en(),.frame_start(frame_start));
        end
    endgenerate
    always @(posedge clk) begin
        if(!ready) begin response_pipe<=0;requests=0;frames=0;end
        else begin
            // R0请求后R3 valid可见，R4沿进入B缓存。
            response_pipe<={response_pipe[2:0],request};
            if(request) requests=requests+1;
            if(frame_start) begin
                frames=frames+1;
                #1;
                if(LEGAL && underrun!==(frames==1)) begin
                    $display("FAIL tb_audio_parameters legal case=%0d unexpected underrun",CASE_ID);$finish;
                end
            end
        end
    end
    initial begin
        repeat(5) @(negedge clk);rst=1;
        repeat(6000) @(negedge clk);
        if(!LEGAL) begin
            $display("UNEXPECTED_ACCEPT tb_audio_parameters illegal case=%0d",CASE_ID);$finish;
        end
        if(frames<3 || requests<3) begin
            $display("FAIL tb_audio_parameters legal case=%0d missing clock events",CASE_ID);$finish;
        end
        $display("PASS tb_audio_parameters case=%0d lead=%0d frames=%0d requests=%0d",CASE_ID,LEAD,frames,requests);
        $finish;
    end
endmodule
