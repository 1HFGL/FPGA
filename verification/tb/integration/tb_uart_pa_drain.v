`timescale 1ns/1ps
// 实际50MHz/48kHz和100000拍消抖；默认钢琴包络不缩短。
// 同时观察发送器待发/活动帧及两个DAC已锁存字，不能只等尾音最终归零。
module tb_uart_pa_drain;
    parameter integer SHORT_TAIL=0;
    parameter integer REQUEST_LEAD_HALF_EDGES=0;
    reg clk=0, rst_n=0;
    reg [1:0] keys=3;
    wire bck,ws,din,pa;
    reg [15:0] serial_word=0, right_word=0, left_word=0;
    integer bits=0, frames=0, nonzero_words=0, quiet_frames=0;
    integer start_frame;
    always #10 clk=~clk;
    instrument_uart_top #(
        .DEBOUNCE_CYCLES(100000),.ROM_FILE("rtl/rom/piano_1024.mem"),
        .ATTACK_SAMPLES(96),.DECAY_SAMPLES(57600),.SUSTAIN_LEVEL(0),
        .RELEASE_SAMPLES(SHORT_TAIL ? 13 : 8640),
        .REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES)
    ) dut(.sys_clk(clk),.sys_rst_n(rst_n),.Key_in(keys),.uart_rx(1'b1),.uart_tx(),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));

    // 对应DAC每16个BCK上升沿锁存一次；在复位段不评价排空，只验证立即静音。
    always @(posedge bck or negedge rst_n) begin
        if(!rst_n) begin bits=0; serial_word=0; right_word=0; left_word=0; end
        else if(dut.audio_ready) begin
            serial_word={serial_word[14:0],din}; bits=bits+1;
            if(bits==16) begin
                if(ws) left_word=serial_word; else right_word=serial_word;
                if(serial_word!=0) nonzero_words=nonzero_words+1;
                bits=0;
            end
        end
    end
    always @(posedge clk) begin
        if(!dut.audio_ready) begin frames=0; quiet_frames=0; end
        else if(dut.u_b.frame_start) begin
            frames=frames+1;
            if(dut.sounding) quiet_frames=0;
            else if(quiet_frames<5) quiet_frames=quiet_frames+1;
        end
        // NBA以及BCK观察回调之后检查，排除同一时间步内的中间状态。
        #1;
        if(dut.audio_ready) begin
            if(pa && (dut.u_b.u_i2s_tx.active_sample!=0 ||
                (dut.u_b.u_i2s_tx.pending_valid && dut.u_b.u_i2s_tx.pending_sample!=0) ||
                right_word!=0 || left_word!=0)) begin
                $display("FAIL PA_DRAIN short=%0d time=%0t active=%0d R=%0d L=%0d",
                    SHORT_TAIL,$time,$signed(dut.u_b.u_i2s_tx.active_sample),
                    $signed(right_word),$signed(left_word)); $finish;
            end
            if(quiet_frames>=4 && !dut.sounding && !pa) begin
                $display("FAIL PA_DRAIN amplifier never shuts down"); $finish;
            end
        end
    end
    task wait_frames;
        input integer count;
        integer origin;
        begin origin=frames; wait(frames>=origin+count); @(negedge clk); end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst_n=1; wait_frames(6);
        if(pa!==1) begin $display("FAIL PA_DRAIN idle"); $finish; end
        keys=2; wait_frames(300); // 2ms消抖后，还保留约4ms正常起音。
        if(pa!==0 || nonzero_words<20) begin $display("FAIL PA_DRAIN no actual tone"); $finish; end
        keys=3;
        wait(dut.sounding===0); @(negedge clk); start_frame=frames;
        wait(pa===1); @(negedge clk);
        if(frames-start_frame>4) begin $display("FAIL PA_DRAIN unbounded mute delay"); $finish; end
        wait_frames(6);
        // 完整排空后再次起音；异步复位不必等正在发送的非零帧排完。
        keys=2; wait_frames(150);
        if(pa!==0) begin $display("FAIL PA_DRAIN restart"); $finish; end
        #3; rst_n=0; #1;
        if(pa!==1) begin $display("FAIL PA_DRAIN async reset"); $finish; end
        keys=3; repeat(5) @(negedge clk); rst_n=1; wait_frames(6);
        if(pa!==1 || right_word!=0 || left_word!=0) begin $display("FAIL PA_DRAIN reset recovery"); $finish; end
        $display("PASS tb_uart_pa_drain short=%0d nonzero_words=%0d",SHORT_TAIL,nonzero_words);
        $finish;
    end
    initial begin #260000000; $display("FAIL PA_DRAIN timeout"); $finish; end
endmodule
