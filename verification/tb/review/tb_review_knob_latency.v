`timescale 1ns/1ps
// 名义50MHz/48kHz、不加速I2C或转换等待。终点是音频域增益/频率比完成
// 斜坡，不含DAC模拟建立、旋钮机械/模拟RC、扬声器；不能称整机延迟实测。
module tb_review_knob_latency;
    reg clk=1'b0, rst_n=1'b0;
    always #10 clk=~clk;
    tri1 sda;
    wire scl,valid,ready,fault,half_ce,frame_start,sample_request;
    wire [13:0] knobs;
    wire [16:0] gain;
    wire [17:0] bend;
    ads1115_knob_if dut(.clk(clk),.rst_n(rst_n),.sda(sda),.scl(scl),
        .knob_value_flat(knobs),.knob_sample_valid(valid),.param_ready(ready),.param_fault(fault));
    ads1115_timed_model adc(.scl(scl),.sda(sda));
    sample_tick #(.AUDIO_CLK_HZ(50000000),.REQUEST_LEAD_HALF_EDGES(2)) tick(
        .clk_audio(clk),.rst_n(rst_n),.bclk_half_ce(half_ce),
        .frame_start(frame_start),.sample_prepare(sample_request));
    piano_controls control(.clk(clk),.rst_n(rst_n),.sample_request(sample_request),
        .knob_value_flat(knobs),.knob_valid(valid),.param_ready(ready),.param_fault(fault),
        .master_gain(gain),.bend_ratio(bend));

    time last_rise=0,last_fall=0,last_sda=0,last_stop=0,start_time=0;
    time min_low=1000000000,min_high=1000000000,max_latency=0;
    time last_pair=0,max_pair=0;
    integer pair_count=0,case_count=0;
    reg start_hold=1'b0,check_bus=1'b0;
    reg valid_last=1'b0;
    // 检查快速模式的数字引脚时序；真实上拉电阻/电容的边沿仍需示波器验证。
    always @(sda) begin
        last_sda=$time;
        if(check_bus && scl && sda===1'b0) begin
            if(last_stop!=0 && $time-last_stop<600) begin
                $display("FAIL I2C bus-free interval"); $stop;
            end
            if(last_rise!=0 && $time-last_rise<600) begin
                $display("FAIL I2C START setup"); $stop;
            end
            start_hold=1'b1; start_time=$time;
        end
        if(check_bus && scl && sda===1'b1) begin
            if(last_rise!=0 && $time-last_rise<600) begin
                $display("FAIL I2C STOP setup"); $stop;
            end
            last_stop=$time;
        end
    end
    always @(posedge scl) begin
        if(check_bus && last_fall!=0) begin
            if($time-last_fall<1300) begin $display("FAIL I2C SCL low"); $stop; end
            if($time-last_fall<min_low) min_low=$time-last_fall;
            if($time-last_sda<100) begin $display("FAIL I2C data setup"); $stop; end
        end
        last_rise=$time;
    end
    always @(negedge scl) begin
        if(check_bus && last_rise!=0) begin
            if($time-last_rise<600) begin $display("FAIL I2C SCL high"); $stop; end
            if($time-last_rise<min_high) min_high=$time-last_rise;
            if(start_hold && $time-start_time<600) begin $display("FAIL I2C START hold"); $stop; end
        end
        start_hold=1'b0; last_fall=$time;
    end
    always @(negedge clk) begin
        if(rst_n) begin
            if(valid && valid_last) begin $display("FAIL knob valid wider than one cycle"); $stop; end
            if(valid && !fault) begin
                pair_count=pair_count+1;
                if(last_pair!=0 && $time-last_pair>max_pair) max_pair=$time-last_pair;
                last_pair=$time;
            end
        end
        valid_last=valid;
    end

    task settle;
        input [16:0] expected_gain;
        input [17:0] expected_bend;
        input integer limit_ns;
        time begun,elapsed;
        begin
            begun=$time;
            while(gain!==expected_gain || bend!==expected_bend || !ready || fault) begin
                @(negedge clk);
                if($time-begun>limit_ns) begin
                    $display("FAIL knob latency: limit_ns=%0d gain=%0d bend=%0d ready=%b fault=%b",
                        limit_ns,gain,bend,ready,fault); $stop;
                end
            end
            elapsed=$time-begun;
            if(limit_ns==10000000) begin
                case_count=case_count+1;
                if(elapsed>max_latency) max_latency=elapsed;
                $display("KNOB case=%0d settled_ns=%0d gain=%0d bend=%0d",case_count,elapsed,gain,bend);
            end
        end
    endtask
    task change_after_sample;
        input integer offset_ns;
        input [15:0] raw0,raw1;
        input [16:0] expected_gain;
        input [17:0] expected_bend;
        integer starts;
        begin
            starts=adc.starts0;
            wait(adc.starts0!=starts);
            #(offset_ns+1);
            adc.input0=raw0; adc.input1=raw1;
            settle(expected_gain,expected_bend,10000000);
        end
    endtask

    initial begin
        #200; rst_n=1'b1; check_bus=1'b1;
        settle(17'd0,18'd65536,800000000);
        $display("KNOB initial_ready_ns=%0d pairs=%0d",$time,pair_count);
        // 覆盖CH0刚开始、转换中、读取附近、CH1开始后，两个旋钮同时变化。
        change_after_sample(0,26400,26400,65536,73562);
        change_after_sample(0,0,0,0,58386);
        change_after_sample(300000,26400,26400,65536,73562);
        change_after_sample(1400000,0,0,0,58386);
        change_after_sample(1800000,26400,26400,65536,73562);
        change_after_sample(2500000,0,0,0,58386);
        change_after_sample(3400000,26400,13200,65536,65536);
        change_after_sample(0,16'hffff,13200,0,65536);
        change_after_sample(0,16'h7fff,13200,65536,65536);
        $display("KNOB max_settled_ns=%0d max_pair_ns=%0d min_scl_low_ns=%0d min_scl_high_ns=%0d",
            max_latency,max_pair,min_low,min_high);

        // NACK时保持最后参数，不能将未完成的一对样本发布给音频；再连接恢复。
        adc.connected=1'b0;
        wait(fault); #100;
        repeat(500000) @(negedge clk);
        if(gain!==17'd65536 || bend!==18'd65536 || ready) begin
            $display("FAIL knob fault retention"); $stop;
        end
        adc.input0=0; adc.input1=0; adc.connected=1'b1;
        settle(17'd0,18'd58386,30000000);

        // 在ADC正在转换时仅复位FPGA，ADC继续完成旧转换；启动等待应防止
        // 新配置被忙碌的ADC忽略。模型并没有跟着FPGA复位清零。
        wait(adc.conversion_busy); #100;
        check_bus=1'b0; rst_n=1'b0; #100;
        if(ready || valid || fault || gain!==17'd65536 || bend!==18'd65536) begin
            $display("FAIL knob reset"); $stop;
        end
        last_rise=0;last_fall=0;last_sda=0;last_stop=0;start_hold=0;
        rst_n=1'b1; check_bus=1'b1;
        settle(17'd0,18'd58386,20000000);
        if(case_count!=9 || adc.reads<20) begin $display("FAIL knob coverage"); $stop; end
        $display("PASS tb_review_knob_latency: 9 phase/boundary cases, timed ADC, fault/reset/recovery");
        $finish;
    end
    initial begin #1500000000; $display("FAIL knob global timeout"); $stop; end
endmodule
