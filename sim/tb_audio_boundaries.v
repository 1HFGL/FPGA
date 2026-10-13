`timescale 1ns/1ps
// 只验证数字接口：50MHz / 48kHz / PT8211的16位左右字。
// 独立相位模型校验帧与请求时刻；期望字不是从DUT缓存寄存器读出的。
module tb_audio_boundaries;
    reg clk=0, rst_n=0;
    always #10 clk=~clk;
    wire [2:0] ready,request,frame,bck,ws,din,underrun,pa;
    wire [15:0] auto_data0,auto_data1;
    wire auto_valid0,auto_valid1;
    reg [15:0] manual_data=0;
    reg manual_valid=0;
    wire [31:0] words0,words1,words2;
    integer cycle=0,phase=0,edge_index=0,last_frame=0,last_request=0;
    integer last_old_request=0,frames_seen=0,requests_seen=0;
    integer windows32=0,windows33=0,epochs=0;
    integer target_cycle;
    reg expected_half,expected_frame,expected_prepare;

    synth_top #(.AUDIO_CLK_HZ(50000000),.REQUEST_LEAD_HALF_EDGES(0),
        .MAX_SAMPLE_LATENCY_CYCLES(4)) old_mode(
        .clk_in(clk),.rst_n(rst_n),.audio_enable(1'b1),
        .sample_data(auto_data0),.sample_valid(auto_valid0),.audio_ready(ready[0]),
        .sample_request(request[0]),.frame_start(frame[0]),.sample_underrun(underrun[0]),
        .i2s_bclk(bck[0]),.i2s_lrclk(ws[0]),.i2s_sdata(din[0]),.pa_en(pa[0]));
    synth_top #(.AUDIO_CLK_HZ(50000000),.REQUEST_LEAD_HALF_EDGES(2),
        .MAX_SAMPLE_LATENCY_CYCLES(4)) early_mode(
        .clk_in(clk),.rst_n(rst_n),.audio_enable(1'b1),
        .sample_data(auto_data1),.sample_valid(auto_valid1),.audio_ready(ready[1]),
        .sample_request(request[1]),.frame_start(frame[1]),.sample_underrun(underrun[1]),
        .i2s_bclk(bck[1]),.i2s_lrclk(ws[1]),.i2s_sdata(din[1]),.pa_en(pa[1]));
    synth_top #(.AUDIO_CLK_HZ(50000000),.REQUEST_LEAD_HALF_EDGES(2),
        .MAX_SAMPLE_LATENCY_CYCLES(4)) manual_mode(
        .clk_in(clk),.rst_n(rst_n),.audio_enable(1'b1),
        .sample_data(manual_data),.sample_valid(manual_valid),.audio_ready(ready[2]),
        .sample_request(request[2]),.frame_start(frame[2]),.sample_underrun(underrun[2]),
        .i2s_bclk(bck[2]),.i2s_lrclk(ws[2]),.i2s_sdata(din[2]),.pa_en(pa[2]));

    // R0发请求，R3沿后valid可见，R4接收。和当前A/B合同一致。
    audio_boundary_source source0(clk,ready[0],request[0],auto_data0,auto_valid0);
    audio_boundary_source source1(clk,ready[1],request[1],auto_data1,auto_valid1);
    audio_boundary_words #(.MANUAL(0)) check0(ready[0],bck[0],ws[0],din[0],underrun[0],words0);
    audio_boundary_words #(.MANUAL(0)) check1(ready[1],bck[1],ws[1],din[1],underrun[1],words1);
    audio_boundary_words #(.MANUAL(1)) check2(ready[2],bck[2],ws[2],din[2],underrun[2],words2);

    // 帧0的第一个半边沿在ready后的第17拍；64位常量避免乘积溢出。
    function integer frame_cycle;
        input integer index;
        reg [63:0] numerator;
        begin
            numerator=(64*index+1)*64'd50000000+64'd3071999;
            frame_cycle=numerator/64'd3072000;
        end
    endfunction

    // 在下降沿驱动下一个上升沿的数据，不与DUT顺序块竞争。
    always @(negedge clk) begin
        manual_valid=0;
        if(ready[2]) begin
            target_cycle=cycle+1;
            if(target_cycle==frame_cycle(1)-1) begin manual_data=16'h1111; manual_valid=1; end
            if(target_cycle==frame_cycle(1))   begin manual_data=16'h2222; manual_valid=1; end
            if(target_cycle==frame_cycle(2)+1) begin manual_data=16'h3333; manual_valid=1; end
            if(target_cycle==frame_cycle(3)+10) begin manual_data=16'h4444; manual_valid=1; end
            if(target_cycle==frame_cycle(3)+11) begin manual_data=16'h5555; manual_valid=1; end
            if(target_cycle==frame_cycle(3)+12) begin manual_data=16'h7fff; manual_valid=1; end
            if(target_cycle==frame_cycle(5)+10) begin manual_data=16'h8000; manual_valid=1; end
            if(target_cycle==frame_cycle(6)+20) begin manual_data=16'hffff; manual_valid=1; end
        end
    end

    always @(posedge clk) begin
        if(!ready[0]) begin
            cycle=0; phase=0; edge_index=0; last_frame=0; last_request=0;
            last_old_request=0; frames_seen=0; requests_seen=0;
        end else begin
            cycle=cycle+1;
            expected_half=(phase+3072000>=50000000);
            expected_frame=expected_half && edge_index==0;
            expected_prepare=expected_half && edge_index==62;
            if(ready!==3'b111 || frame!=={3{expected_frame}} ||
               request[0]!==expected_frame || request[1]!==expected_prepare || request[2]!==expected_prepare) begin
                $display("FAIL audio boundaries schedule cycle=%0d edge=%0d frame=%b request=%b",cycle,edge_index,frame,request); $finish;
            end
            if(bck[0]!==bck[1] || bck[1]!==bck[2] || ws[0]!==ws[1] || ws[1]!==ws[2]) begin
                $display("FAIL request phase changed serial clock/channel"); $finish;
            end
            if(request[0]) begin
                if(last_old_request!=0 && (cycle-last_old_request<1041 || cycle-last_old_request>1042)) begin
                    $display("FAIL old request period"); $finish;
                end
                last_old_request=cycle;
            end
            if(request[1]) begin
                if(last_request!=0 && (cycle-last_request<1041 || cycle-last_request>1042)) begin
                    $display("FAIL early request period"); $finish;
                end
                last_request=cycle; requests_seen=requests_seen+1;
            end
            if(frame[0]) begin
                if(cycle!=frame_cycle(frames_seen)) begin $display("FAIL independent frame formula"); $finish; end
                if(last_frame!=0 && (cycle-last_frame<1041 || cycle-last_frame>1042)) begin
                    $display("FAIL frame period"); $finish;
                end
                if(frames_seen!=0) begin
                    if(cycle-last_request==32) windows32=windows32+1;
                    else if(cycle-last_request==33) windows33=windows33+1;
                    else begin $display("FAIL lead window actual=%0d",cycle-last_request); $finish; end
                    if(requests_seen!=frames_seen) begin $display("FAIL request lost/duplicated"); $finish; end
                end
                frames_seen=frames_seen+1; last_frame=cycle;
            end
            phase=phase+3072000;
            if(expected_half) begin
                phase=phase-50000000;
                if(edge_index==63) edge_index=0; else edge_index=edge_index+1;
            end
        end
    end

    initial begin
        #77; rst_n=1; // 故意避开时钟沿，内部同步释放仍必须一致。
        wait(words0>=18 && words1>=18 && words2>=18);
        repeat(5) @(posedge bck[0]);
        #3; rst_n=0; #1;
        if(ready!==0 || bck!==3'b111 || din!==0 || pa!==3'b111) begin
            $display("FAIL asynchronous midword reset outputs"); $finish;
        end
        epochs=epochs+1;
        #73; rst_n=1;
        wait(words0>=18 && words1>=18 && words2>=18);
        epochs=epochs+1;
        if(windows32==0 || windows33==0 || epochs!=2) begin
            $display("FAIL boundary coverage windows32=%0d windows33=%0d epochs=%0d",windows32,windows33,epochs); $finish;
        end
        $display("PASS tb_audio_boundaries: before/same/after frame, last-wins, empty, signed extrema, R/L, R4, reset/restart; lead32=%0d lead33=%0d",windows32,windows33);
        $finish;
    end
    initial begin #1000000; $display("FAIL audio boundary timeout"); $finish; end
endmodule

module audio_boundary_source(input wire clk,rst_n,request,
    output wire [15:0] data,output wire valid);
    reg [3:0] valid_pipe=0;
    reg [15:0] sequence=0;
    integer cycle=0,request_at=0;
    assign data=16'h3157 ^ sequence;
    assign valid=valid_pipe[3];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin valid_pipe<=0; sequence<=0; cycle=0; request_at=0; end
        else begin
            cycle=cycle+1;
            valid_pipe<={valid_pipe[2:0],request};
            if(request) begin sequence<=sequence+16'd1; request_at=cycle; end
            if(valid && cycle-request_at!=4) begin $display("FAIL source is not R4"); $finish; end
        end
    end
endmodule

module audio_boundary_words #(parameter integer MANUAL=0)(
    input wire rst_n,bck,ws,din,underrun,output reg [31:0] words=0);
    integer bits=0,frame_number;
    reg [15:0] received=0,expected;
    reg expected_empty;
    always @(posedge bck or negedge rst_n) begin
        if(!rst_n) begin words=0; bits=0; received=0; end
        else begin
            frame_number=words/2;
            expected_empty=(frame_number==0);
            if(MANUAL) begin
                case(frame_number)
                    1: expected=16'h1111;
                    2: expected=16'h2222;
                    3: expected=16'h3333;
                    4: expected=16'h7fff;
                    6: expected=16'h8000;
                    7: expected=16'hffff;
                    default: begin expected=0; expected_empty=1; end
                endcase
            end else if(frame_number==0) expected=0;
            else expected=16'h3157 ^ frame_number[15:0];
            if(ws!==(words%2) || underrun!==expected_empty) begin
                $display("FAIL boundary channel/underrun manual=%0d frame=%0d ws=%b empty=%b",MANUAL,frame_number,ws,underrun); $finish;
            end
            received={received[14:0],din}; bits=bits+1;
            if(bits==16) begin
                if(received!==expected) begin
                    $display("FAIL boundary DAC manual=%0d frame=%0d channel=%0d expected=%h actual=%h",MANUAL,frame_number,words%2,expected,received); $finish;
                end
                words=words+1; bits=0;
            end
        end
    end
endmodule
