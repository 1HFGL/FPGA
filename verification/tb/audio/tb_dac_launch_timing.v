`timescale 1ns/1ps
// 数字发射端检查，不把零延迟仿真当成DAC引脚电气测量。
// 不读取DUT缓存；期望字只从公开输入和帧事件建立。
module tb_dac_launch_timing;
    parameter integer INJECT = 0; // 1/2故意在接收沿翻转DIN/WS，仅供负向验证
    reg clk=0, rst_n=0, valid=0;
    reg [15:0] data=0;
    wire ready,request,frame,bck,ws,din,underrun,pa;
    wire observed_din=din ^ ((INJECT==1) && bck);
    wire observed_ws=ws ^ ((INJECT==2) && bck);
    integer drive_count=0, epochs=0, rises=0, frames=0, silent_frames=0;
    integer short_halves=0,long_halves=0,short_frames=0,long_frames=0;
    integer din_up=0,din_down=0,ws_up=0,ws_down=0,slot_bit=0;
    reg prev_bck=1,prev_ws=1,prev_din=0,tracking=0;
    reg pending_valid=0;
    reg [15:0] pending_word=0,expected_word=0;
    time last_edge=0,last_rise=0,last_frame=0,last_din=0,last_ws=0;
    time elapsed,min_setup_din=1000000,min_hold_din=1000000;
    time min_setup_ws=1000000,min_hold_ws=1000000;
    always #10 clk=~clk;
    synth_top #(.AUDIO_CLK_HZ(50000000),.SAMPLE_RATE_HZ(48000),
        .REQUEST_LEAD_HALF_EDGES(60),.MAX_SAMPLE_LATENCY_CYCLES(924)) dut(
        .clk_in(clk),.rst_n(rst_n),.audio_enable(1'b1),.sample_data(data),
        .sample_valid(valid),.audio_ready(ready),.sample_request(request),
        .frame_start(frame),.sample_underrun(underrun),
        .i2s_bclk(bck),.i2s_lrclk(ws),.i2s_sdata(din),.pa_en(pa));

    // 在系统下降沿驱动；连续valid、长时间欠载、符号边界和交替位均覆盖。
    always @(negedge clk) begin
        drive_count=drive_count+1;
        valid=ready && ((drive_count/4000)%3!=1);
        case((drive_count/1100)%6)
            0:data=16'h5555; 1:data=16'haaaa; 2:data=16'h8000;
            3:data=16'h7fff; 4:data=16'hffff; default:data=16'h0000;
        endcase
    end
    task fail;
        input [8*90-1:0] message;
        begin $display("FAIL DAC %0s at %0t",message,$time); $finish; end
    endtask

    // NBA更新后统一检查，避免同时改变BCK/数据时的调度竞争。
    always @(posedge clk) begin
        if(!ready) begin
            pending_valid=0;pending_word=0;expected_word=0;
            tracking=0;last_edge=0;last_rise=0;last_frame=0;slot_bit=0;
        end else begin
            if(frame) begin
                expected_word=pending_valid ? pending_word : 16'd0;
                if(!pending_valid) silent_frames=silent_frames+1;
                pending_valid=valid;
                slot_bit=0;
                frames=frames+1;
                if(last_frame!=0) begin
                    elapsed=$time-last_frame;
                    if(elapsed==20820)short_frames=short_frames+1;
                    else if(elapsed==20840)long_frames=long_frames+1;
                    else fail("frame period is not 1041/1042 clocks");
                end
                last_frame=$time;
            end else if(valid)pending_valid=1;
            if(valid)pending_word=data;
        end
        #1;
        if(!ready) begin
            if({bck,ws,din}!==3'b110)fail("reset output state");
        end else if(!tracking) begin
            tracking=1;last_din=$time;last_ws=$time;
        end else begin
            if((^{bck,observed_ws,observed_din})===1'bx)fail("unknown output");
            if(bck!=prev_bck) begin
                if(last_edge!=0) begin
                    elapsed=$time-last_edge;
                    if(elapsed==320)short_halves=short_halves+1;
                    else if(elapsed==340)long_halves=long_halves+1;
                    else fail("BCK half period is not 16/17 clocks");
                end
                last_edge=$time;
            end
            if(observed_din!=prev_din) begin
                if(!(prev_bck && !bck))fail("DIN changed outside falling BCK");
                if(last_rise!=0) begin
                    elapsed=$time-last_rise;
                    if(elapsed<320)fail("DIN hold window below 320ns");
                    if(elapsed<min_hold_din)min_hold_din=elapsed;
                end
                if(observed_din)din_up=din_up+1;else din_down=din_down+1;
                last_din=$time;
            end
            if(observed_ws!=prev_ws) begin
                if(!(prev_bck && !bck))fail("WS changed outside falling BCK");
                if(last_rise!=0) begin
                    elapsed=$time-last_rise;
                    if(elapsed<320)fail("WS hold window below 320ns");
                    if(elapsed<min_hold_ws)min_hold_ws=elapsed;
                end
                if(observed_ws)ws_up=ws_up+1;else ws_down=ws_down+1;
                last_ws=$time;
            end
            if(!prev_bck && bck) begin
                elapsed=$time-last_din;
                if(elapsed<320)fail("DIN setup window below 320ns");
                if(elapsed<min_setup_din)min_setup_din=elapsed;
                elapsed=$time-last_ws;
                if(elapsed<320)fail("WS setup window below 320ns");
                if(elapsed<min_setup_ws)min_setup_ws=elapsed;
                if(observed_ws !== (slot_bit>=16))fail("right/left slot selection");
                if(observed_din !== expected_word[15-(slot_bit%16)])fail("serialized sample mismatch");
                slot_bit=(slot_bit+1)%32;
                rises=rises+1;last_rise=$time;
            end
        end
        prev_bck=bck;prev_din=observed_din;prev_ws=observed_ws;
    end
    integer e;
    initial begin
        #37;rst_n=1;
        for(e=0;e<4;e=e+1) begin
            repeat(10000+e*13)@(negedge clk);
            #3;rst_n=0;#47;rst_n=1;epochs=epochs+1;
        end
        repeat(10000)@(negedge clk);
        #5;
        if(rises<1000 || frames<40 || silent_frames<5 ||
            short_halves==0 || long_halves==0 || short_frames==0 || long_frames==0 ||
            din_up==0 || din_down==0 || ws_up==0 || ws_down==0)fail("coverage missing");
        if(min_setup_din!=320 || min_hold_din!=320 || min_setup_ws!=320 || min_hold_ws!=320)
            fail("shortest setup/hold boundary not exercised");
        $display("PASS tb_dac_launch_timing: epochs=%0d rises=%0d frames=%0d underrun_frames=%0d",epochs+1,rises,frames,silent_frames);
        $display("DAC_WINDOWS_NS DIN_SETUP=%0d DIN_HOLD=%0d WS_SETUP=%0d WS_HOLD=%0d",min_setup_din,min_hold_din,min_setup_ws,min_hold_ws);
        $finish;
    end
    initial begin #2000000;fail("timeout");end
endmodule
