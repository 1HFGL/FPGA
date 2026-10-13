`timescale 1ns/1ps

module sample_tick_tb;
    reg clk_audio = 1'b0;
    reg rst_n = 1'b0;
    wire bclk_half_ce;
    wire frame_start;
    integer half_edges = 0;
    integer frames = 0;
    integer edges_in_frame = 0;

    always #5 clk_audio = ~clk_audio;

    // 缩小频率数值以加快仿真；比例仍是每帧 64 个 BCK 半周期。
    sample_tick #(
        .AUDIO_CLK_HZ(1000),
        .SAMPLE_RATE_HZ(10),
        .SLOT_BITS(16)
    ) dut (
        .clk_audio(clk_audio),
        .rst_n(rst_n),
        .bclk_half_ce(bclk_half_ce),
        .frame_start(frame_start)
    );

    always @(posedge clk_audio) begin
        if (rst_n) begin
            if (frame_start && !bclk_half_ce)
                begin $display("FAIL: frame_start not aligned with bclk_half_ce"); $finish; end
            if (bclk_half_ce) begin
                half_edges = half_edges + 1;
                if (frame_start) begin
                    if (frames > 0 && edges_in_frame != 64)
                        begin $display("FAIL: wrong frame length: %0d", edges_in_frame); $finish; end
                    frames = frames + 1;
                    edges_in_frame = 0;
                end
                edges_in_frame = edges_in_frame + 1;
            end
        end
    end

    initial begin
        repeat (3) @(negedge clk_audio);
        rst_n = 1'b1;
        repeat (1000) @(negedge clk_audio);
        if (half_edges != 640 || frames != 10)
            begin $display("FAIL: first count failed: half_edges=%0d frames=%0d", half_edges, frames); $finish; end

        // 运行中复位后应从同一个帧位置重新开始。
        rst_n = 1'b0;
        #1;
        if (bclk_half_ce !== 1'b0 || frame_start !== 1'b0)
            begin $display("FAIL: enable pulse during reset"); $finish; end
        half_edges = 0;
        frames = 0;
        edges_in_frame = 0;
        repeat (2) @(negedge clk_audio);
        rst_n = 1'b1;
        repeat (1000) @(negedge clk_audio);
        if (half_edges != 640 || frames != 10)
            begin $display("FAIL: post-reset count failed: half_edges=%0d frames=%0d", half_edges, frames); $finish; end

        $display("PASS sample_tick_tb: 640 half-edges, 10 frames, reset");
        $finish;
    end
endmodule
