`timescale 1ns/1ps
// 独立新增测试：真实板级复位链+厂商PLL/OSER模型，不修改已有HDMI或队友TB。
// 每次恢复清空记分板，仅首次允许寻找固定流水线偏移，之后逐字检查四路连续输出。
module tb_review_hdmi_reset_recovery;
    reg sys_clk=0, rst_n=0, hpd=1;
    always #10 sys_clk=~sys_clk;
    GSR GSR(.GSRI(1'b1));
    wire [2:0] dp,dn;
    wire cp,cn,tx,bck,ws,din,pa,scl;
    tri1 sda;
    piano_hdmi_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),
        .DEBOUNCE_CYCLES(8),.DISPLAY_LOCK_CYCLES(8)) dut(
        .sys_clk(sys_clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(13'h1fff),
        .uart_rx(1'b1),.hdmi_hpd(hpd),.uart_tx(tx),.HP_BCK(bck),.HP_WS(ws),
        .HP_DIN(din),.PA_EN(pa),.knob_sda(sda),.knob_scl(scl),
        .tmds_data_p(dp),.tmds_data_n(dn),.tmds_clk_p(cp),.tmds_clk_n(cn));
    wire video_ready=dut.video_release[1];
    wire [3:0] serializer_reset={dut.u_tx.g_lane[3].u_serializer.RESET,
        dut.u_tx.g_lane[2].u_serializer.RESET,dut.u_tx.g_lane[1].u_serializer.RESET,
        dut.u_tx.g_lane[0].u_serializer.RESET};
    reg [23:0] pattern_rgb=0;
    reg pattern_de=0,pattern_hs=0,pattern_vs=0;
    reg [15:0] pattern_count=0;
    // 仅替换绘制器输出作为可重复视频刺激；复位、PLL、编码器和四路OSER均为正式RTL。
    always @(negedge dut.pixel_clk) begin
        pattern_count=pattern_count+1'b1;
        pattern_rgb={pattern_count[7:0],pattern_count[15:8]^8'h6b,pattern_count[7:0]^8'ha5};
        pattern_de=(pattern_count%23)<18;
        pattern_hs=pattern_count[0];pattern_vs=pattern_count[1];
    end
    reg [39:0] expected[0:511];
    reg [9:0] word0,word1,word2,word3;
    reg [39:0] actual;
    reg aligned=0,previous_cp=0;
    integer epoch=0,pixels=0,bit_index=0,last_match=-1,matched=0,total_matched=0;
    integer candidate=-1,match_count=0,i,passed_epochs=0;
    always @(negedge video_ready) begin
        pixels=0;bit_index=0;last_match=-1;matched=0;aligned=0;previous_cp=0;
    end
    always @(posedge dut.pixel_clk) begin
        if(video_ready) begin
            if(pixels>=512) begin $display("FAIL HDMI reset bounded scoreboard epoch=%0d",epoch);$finish;end
            // OSER在此沿读取更新前的编码字，与独立输出组字比较，不接受跳字或乱序。
            expected[pixels]=dut.u_tx.symbols;pixels=pixels+1;
            if(pixels>40 && last_match<0) begin
                $display("FAIL HDMI reset word alignment epoch=%0d",epoch);$finish;
            end
        end
    end
    always @(dut.serial_clk) begin
        #0.2;
        if(video_ready) begin
            if({cn,dn}!==~{cp,dp}) begin $display("FAIL HDMI reset differential epoch=%0d",epoch);$finish;end
            if(previous_cp && !cp) begin
                if(aligned && bit_index!=0) begin $display("FAIL HDMI reset clock word length epoch=%0d",epoch);$finish;end
                aligned=1;bit_index=0;
            end
            if(aligned) begin
                word0[bit_index]=dp[0];word1[bit_index]=dp[1];
                word2[bit_index]=dp[2];word3[bit_index]=cp;
                if(bit_index==9) begin
                    actual={word3,word2,word1,word0};
                    if(word3!==10'b1111100000) begin $display("FAIL HDMI reset clock bits epoch=%0d",epoch);$finish;end
                    if(last_match<0) begin
                        candidate=-1;match_count=0;
                        for(i=0;i<pixels;i=i+1) if(actual===expected[i]) begin candidate=i;match_count=match_count+1;end
                        if(match_count==1) last_match=candidate;
                    end else begin
                        last_match=last_match+1;
                        if(last_match>=pixels || actual!==expected[last_match]) begin
                            $display("FAIL HDMI reset word mismatch epoch=%0d index=%0d got=%h expected=%h",epoch,last_match,actual,expected[last_match]);$finish;
                        end
                        matched=matched+1;total_matched=total_matched+1;
                    end
                end
                if(bit_index==9) bit_index=0;else bit_index=bit_index+1;
            end
            previous_cp=cp;
        end else begin aligned=0;previous_cp=0;bit_index=0;end
    end
    task assert_reset;
        begin
            #1;
            if(dut.display_reset!==0 || video_ready!==0 || serializer_reset!==4'hf) begin
                $display("FAIL HDMI reset asynchronous assertion epoch=%0d resets=%b",epoch,serializer_reset);$finish;
            end
        end
    endtask
    task check_epoch;
        begin
            wait(video_ready);wait(matched>=128);@(negedge sys_clk);
            if(serializer_reset!==0) begin $display("FAIL HDMI reset release epoch=%0d",epoch);$finish;end
            passed_epochs=passed_epochs+1;
            $display("CASE HDMI reset recovery epoch=%0d checked_words=%0d",epoch,matched);
        end
    endtask
    integer phase;
    initial begin
        force dut.rgb=pattern_rgb;force dut.de=pattern_de;
        force dut.hs=pattern_hs;force dut.vs=pattern_vs;
        #105;rst_n=1;check_epoch();
        // 在10个串行半周期位置拔屏，含短脉冲和资格检查中再次拔屏。
        for(phase=0;phase<10;phase=phase+1) begin
            epoch=epoch+1;
            @(posedge dut.pixel_clk);repeat(phase)@(dut.serial_clk);#0.35;hpd=0;
            assert_reset();#(13+phase*3);hpd=1;
            if(phase==5) begin #57;hpd=0;assert_reset();#31;hpd=1;end
            check_epoch();
        end
        // 失锁时分别保持时钟、暂停串行时钟、暂停两个时钟；模型不模拟模拟亚稳态。
        for(phase=0;phase<3;phase=phase+1) begin
            epoch=epoch+1;
            @(negedge dut.serial_clk);#0.65;force dut.pll_locked=1'b0;
            if(phase>=1) force dut.serial_clk=1'b0;
            if(phase==2) force dut.pixel_clk=1'b0;
            assert_reset();#73;
            if(phase>=1) release dut.serial_clk;
            if(phase==2) release dut.pixel_clk;
            release dut.pll_locked;
            check_epoch();
        end
        // 系统复位会真实复位厂商PLL；每次重新锁定后再检查完整输出。
        for(phase=0;phase<3;phase=phase+1) begin
            epoch=epoch+1;
            @(dut.serial_clk);#(0.15+phase*0.3);rst_n=0;
            assert_reset();#(41+phase*17);rst_n=1;
            check_epoch();
        end
        if(passed_epochs!=17 || total_matched<2176) begin $display("FAIL HDMI reset coverage");$finish;end
        $display("PASS tb_review_hdmi_reset_recovery: 17 epochs, 10 bit phases, HPD bounce, lock/clock stop, PLL reset, four lanes (%0d words)",total_matched);
        $finish;
    end
    initial begin #2000000;$display("FAIL HDMI reset recovery timeout epoch=%0d matched=%0d",epoch,matched);$finish;end
endmodule
