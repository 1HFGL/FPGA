`timescale 1ns/1ps

// A+B 联合自检：请求/有效时刻、帧缓冲、左右声道、变调及中途复位。
module tb_single_tone_ab;
    reg clk_in = 1'b0;
    reg rst_n = 1'b0;
    reg audio_enable = 1'b0;
    reg [31:0] phase_inc = 32'h40000000;
    wire sample_underrun;
    wire i2s_bclk;
    wire i2s_lrclk;
    wire i2s_sdata;
    wire pa_en;

    // 缩小的频率参数仅加速仿真：100 个主时钟周期约为一个音频帧。
    // 相位增量先取 1/4 周期，随后改为 1/2 周期，便于独立预测正弦样本。
    single_tone_demo_top #(
        .AUDIO_CLK_HZ(1000),
        .SAMPLE_RATE_HZ(10)
    ) dut (
        .clk_in(clk_in),
        .rst_n(rst_n),
        .audio_enable(audio_enable),
        .phase_inc(phase_inc),
        .sample_underrun(sample_underrun),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_sdata(i2s_sdata),
        .pa_en(pa_en)
    );

    always #5 clk_in = ~clk_in;

    reg [31:0] reference_phase;
    reg [15:0] expected_frame [0:31];
    reg previous_request;
    reg [15:0] previous_sample;
    reg request_at_edge;
    reg valid_at_edge;
    reg [15:0] data_at_edge;
    reg [15:0] expected_now;
    integer request_count;
    integer word_index;
    integer bit_count;
    reg [15:0] received_word;
    reg observed_bit;

    // 独立参考只使用四个正弦象限点，不读取 DUT 的 ROM/内部相位。
    function [15:0] quarter_sine;
        input [9:0] addr;
        begin
            case (addr)
                10'd0:   quarter_sine = 16'h0000;
                10'd256: quarter_sine = 16'h7fff;
                10'd512: quarter_sine = 16'h0000;
                10'd768: quarter_sine = 16'h8001;
                default: quarter_sine = 16'hxxxx;
            endcase
        end
    endfunction

    // 在时钟沿之前记录请求/旧 valid，沿后检查 A 的寄存器结果和 B 的缓冲。
    always @(posedge clk_in) begin
        if (!rst_n) begin
            reference_phase = 32'd0;
            request_count = 0;
            previous_request = 1'b0;
            previous_sample = 16'd0;
            expected_frame[0] = 16'd0;
        end else begin
            request_at_edge = dut.sample_request;
            valid_at_edge = dut.sample_valid;
            data_at_edge = dut.sample_data;
            if (!dut.audio_ready && request_at_edge !== 1'b0)
                $fatal(1, "request while audio reset is active");
            if (valid_at_edge !== previous_request)
                $fatal(1, "sample_valid not held for exactly one cycle: t=%0t", $time);
            if (valid_at_edge && data_at_edge !== previous_sample)
                $fatal(1, "sample changed before B accepted it: t=%0t", $time);

            if (request_at_edge) begin
                expected_now = quarter_sine(reference_phase[31:22]);
                if (^expected_now === 1'bx)
                    $fatal(1, "unexpected reference address %0d", reference_phase[31:22]);
                expected_frame[request_count + 1] = expected_now;
                reference_phase = reference_phase + phase_inc;
                request_count = request_count + 1;
                if (request_count > 30)
                    $fatal(1, "test reference array exceeded");
                previous_sample = expected_now;
            end
            previous_request = request_at_edge;

            #1; // NBA 更新完成后检查：A 沿后有效，B 下一沿才取到它。
            if (dut.sample_valid !== request_at_edge)
                $fatal(1, "A valid timing wrong after request: t=%0t", $time);
            if (request_at_edge && dut.sample_data !== expected_now)
                $fatal(1, "A DDS sample mismatch: request=%0d expected=%h actual=%h",
                       request_count, expected_now, dut.sample_data);
            if (valid_at_edge &&
                (dut.u_synth_top.u_i2s_tx.pending_valid !== 1'b1 ||
                 dut.u_synth_top.u_i2s_tx.pending_sample !== data_at_edge))
                $fatal(1, "B did not buffer A sample on following clock: t=%0t", $time);
        end
    end

    // PT8211-S 在 BCLK 上升沿采样；一帧的右、左字都应是上一请求的样本。
    always @(posedge i2s_bclk or negedge rst_n) begin
        if (!rst_n) begin
            word_index = 0;
            bit_count = 0;
            received_word = 16'd0;
        end else if (dut.audio_ready) begin
            if (bit_count == 0) begin
                if (i2s_lrclk !== (word_index % 2))
                    $fatal(1, "wrong channel: word=%0d WS=%b", word_index, i2s_lrclk);
                if (sample_underrun !== (word_index < 2))
                    $fatal(1, "wrong underrun: frame=%0d flag=%b", word_index / 2,
                           sample_underrun);
            end
            observed_bit = i2s_sdata;
`ifdef AB_NEGATIVE_CONTROL
            // 负向验证只污染测试平台观察值，不修改可交付 RTL。
            if (word_index == 2 && bit_count == 0)
                observed_bit = ~observed_bit;
`endif
            received_word = {received_word[14:0], observed_bit};
            bit_count = bit_count + 1;
            if (bit_count == 16) begin
                if (received_word !== expected_frame[word_index / 2])
                    $fatal(1, "serial mismatch: frame=%0d channel=%0d expected=%h actual=%h",
                           word_index / 2, word_index % 2,
                           expected_frame[word_index / 2], received_word);
                bit_count = 0;
                word_index = word_index + 1;
            end
        end
    end

    initial begin
        #50000;
        $fatal(1, "A+B joint simulation timed out");
    end

    initial begin
        repeat (3) @(negedge clk_in);
        if (pa_en !== 1'b1 || dut.audio_ready !== 1'b0)
            $fatal(1, "reset did not keep audio disabled");
        rst_n = 1'b1;
        @(posedge clk_in); #1;
        if (dut.audio_ready !== 1'b0)
            $fatal(1, "audio reset released before first clock completed");
        @(posedge clk_in); #1;
        if (dut.audio_ready !== 1'b1 || pa_en !== 1'b1)
            $fatal(1, "audio reset did not release after second clock");
        @(negedge clk_in);
        audio_enable = 1'b1;
        #1;
        if (pa_en !== 1'b0)
            $fatal(1, "amplifier did not enable");

        wait (word_index >= 12); // 先检查六帧 1/4 周期增量。
        @(negedge clk_in);
        phase_inc = 32'h80000000; // 实时变调，参考相位不清零。
        wait (word_index >= 22); // 再检查五帧变调后的连续性。
        repeat (5) @(posedge i2s_bclk);
        @(negedge clk_in);
        rst_n = 1'b0; // 字发送中间复位。
        #1;
        if (pa_en !== 1'b1 || dut.audio_ready !== 1'b0 ||
            i2s_bclk !== 1'b1 || i2s_sdata !== 1'b0)
            $fatal(1, "unsafe output immediately after reset assertion");
        repeat (3) @(negedge clk_in);
        #1;
        if (dut.sample_valid !== 1'b0 || dut.sample_data !== 16'sd0 ||
            dut.u_voice_dds.u_phase_acc.phase !== 32'd0)
            $fatal(1, "A synchronous state not cleared during reset");
        phase_inc = 32'h40000000;
        rst_n = 1'b1;
        @(posedge clk_in); #1;
        if (dut.audio_ready !== 1'b0)
            $fatal(1, "restart released audio reset too early");
        @(posedge clk_in); #1;
        if (dut.audio_ready !== 1'b1)
            $fatal(1, "restart did not release audio reset");
        wait (word_index >= 12); // 复位后必须重新经历首帧静音和正弦序列。

        if (request_count < 6)
            $fatal(1, "too few A+B requests after reset");
        $display("PASS tb_single_tone_ab: request/valid, next-frame serial, pitch, reset");
        $finish;
    end
endmodule
