`timescale 1ns/1ps

module synth_top_tb;
    reg clk_in = 1'b0;
    reg rst_n = 1'b0;
    reg audio_enable = 1'b0;
    reg signed [15:0] sample_data = 16'sd0;
    reg sample_valid = 1'b0;
    wire audio_ready;
    wire sample_request;
    wire sample_underrun;
    wire i2s_bclk;
    wire i2s_lrclk;
    wire i2s_sdata;
    wire pa_en;
    integer request_index = 0;
    integer word_index = 0;
    integer bit_count = 0;
    reg [15:0] received_word = 16'd0;

    always #5 clk_in = ~clk_in;

    synth_top #(
        .AUDIO_CLK_HZ(1000),
        .SAMPLE_RATE_HZ(10),
        .SAMPLE_BITS(16),
        .SLOT_BITS(16)
    ) dut (
        .clk_in(clk_in),
        .rst_n(rst_n),
        .audio_enable(audio_enable),
        .sample_data(sample_data),
        .sample_valid(sample_valid),
        .audio_ready(audio_ready),
        .sample_request(sample_request),
        .sample_underrun(sample_underrun),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_sdata(i2s_sdata),
        .pa_en(pa_en)
    );

    // 模拟 A：请求后的下一拍返回样本；第三次请求故意不返回。
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            request_index <= 0;
            sample_data <= 16'sd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            if (sample_request) begin
                case (request_index)
                    0: begin sample_data <= 16'hA55A; sample_valid <= 1'b1; end
                    1: begin sample_data <= 16'h5AA5; sample_valid <= 1'b1; end
                    3: begin sample_data <= 16'h8000; sample_valid <= 1'b1; end
                    4: begin sample_data <= 16'h7FFF; sample_valid <= 1'b1; end
                    default: begin end
                endcase
                request_index <= request_index + 1;
            end
        end
    end

    function [15:0] expected_sample;
        input integer frame_number;
        begin
            case (frame_number)
                1: expected_sample = 16'hA55A;
                2: expected_sample = 16'h5AA5;
                4: expected_sample = 16'h8000;
                5: expected_sample = 16'h7FFF;
                default: expected_sample = 16'h0000;
            endcase
        end
    endfunction

    function expected_underrun;
        input integer frame_number;
        begin
            expected_underrun = (frame_number == 0 || frame_number == 3 ||
                                 frame_number >= 6);
        end
    endfunction

    // 模拟 PT8211 在 BCK 上升沿采样，并逐字比较右、左声道。
    always @(posedge i2s_bclk) begin
        if (rst_n && dut.audio_rst_n) begin
            if (bit_count == 0) begin
                if (i2s_lrclk !== (word_index % 2))
                    begin $display("FAIL: wrong WS: word=%0d WS=%b", word_index, i2s_lrclk); $finish; end
                if (sample_underrun !== expected_underrun(word_index / 2))
                    begin $display("FAIL: wrong underrun status: frame=%0d", word_index / 2); $finish; end
            end
            // 可选负向验证：故意翻转一个观察位，检查测试平台能否报错。
`ifdef AUDIO_NEGATIVE_CONTROL
            if (word_index == 2 && bit_count == 0)
                received_word = {received_word[14:0], ~i2s_sdata};
            else
`endif
                received_word = {received_word[14:0], i2s_sdata};
            bit_count = bit_count + 1;
            if (bit_count == 16) begin
                if (received_word !== expected_sample(word_index / 2))
                    begin $display("FAIL: wrong serial sample: frame=%0d channel=%0d expected=%h actual=%h",
                           word_index / 2, word_index % 2,
                           expected_sample(word_index / 2), received_word); $finish; end
                bit_count = 0;
                word_index = word_index + 1;
            end
        end
    end

    initial begin
        #20000;
        begin $display("FAIL: simulation timeout"); $finish; end
    end

    initial begin
        repeat (3) @(negedge clk_in);
        if (pa_en !== 1'b1)
            begin $display("FAIL: amplifier not off during reset"); $finish; end
        rst_n = 1'b1;
        repeat (4) @(negedge clk_in);
        audio_enable = 1'b1;
        #1;
        if (pa_en !== 1'b0)
            begin $display("FAIL: amplifier did not enable"); $finish; end

        wait (word_index >= 12); // 检查六帧：正常、缺样本、正负满幅。
        repeat (5) @(posedge i2s_bclk);
        #1;
        rst_n = 1'b0; // 在串行字中间复位。
        #1;
        if (pa_en !== 1'b1 || i2s_bclk !== 1'b1 || i2s_sdata !== 1'b0)
            begin $display("FAIL: unsafe outputs after mid-word reset"); $finish; end
        word_index = 0;
        bit_count = 0;
        received_word = 16'd0;
        repeat (3) @(negedge clk_in);
        rst_n = 1'b1;
        wait (word_index >= 4); // 复位后重新检查静音帧和第一有效帧。

        $display("PASS synth_top_tb: serial data, channels, underrun, PA, reset");
        $finish;
    end
endmodule
