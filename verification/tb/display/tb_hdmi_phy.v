`timescale 1ns/1ps
// 使用安装版高云原语模型，不用自制OSER模型掩盖真实位序或像素边界问题。
module tb_hdmi_phy;
    reg sys_clk=0,rst=0;
    wire pixel_clk,serial_clk,locked,ready;
    always #10 sys_clk=~sys_clk;
    GSR GSR(.GSRI(1'b1));
    hdmi_clock_60k u_clk(.sys_clk(sys_clk),.rst_n(rst),.pixel_clk(pixel_clk),.serial_clk(serial_clk),.locked(locked));
    hdmi_reset_guard #(.LOCK_CYCLES(8)) guard(.sys_clk(sys_clk),.rst_n(rst),.pll_locked(locked),.display_rst_n(ready));
    reg [23:0] rgb=24'hc35a96;
    reg [1:0] ctr=0;
    reg de=0;
    wire [2:0] dp,dn;
    wire cp,cn;
    dvi_tx_gowin dut(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst_n(ready),
        .rgb(rgb),.de(de),.hsync(ctr[0]),.vsync(ctr[1]),
        .tmds_data_p(dp),.tmds_data_n(dn),.tmds_clk_p(cp),.tmds_clk_n(cn));
    reg [9:0] serial_word[0:3];
    reg [39:0] expected_words[0:2047];
    reg [39:0] actual;
    integer pixel_count=0,bit_count=0,serial_count=0,i,match_index,match_count,matched=0,last_match=-1;
    reg aligned=0,previous_clock=0;
    real prev_pixel=0,prev_serial=0;
    always @(posedge pixel_clk)begin
        if(ready)begin
            if(prev_pixel>0 && ($realtime-prev_pixel<20.40 || $realtime-prev_pixel>20.42))begin $display("FAIL pixel PLL rate");$finish;end
            prev_pixel=$realtime;
            // OSER在此沿采集的是编码器更新前的字。
            expected_words[pixel_count]=dut.symbols;pixel_count=pixel_count+1;
            if(pixel_count>1900)begin $display("FAIL PHY bounded queue");$finish;end
        end
    end
    always @(posedge serial_clk)begin
        if(ready)begin
            if(prev_serial>0 && ($realtime-prev_serial<4.07 || $realtime-prev_serial>4.10))begin $display("FAIL serial PLL rate");$finish;end
            prev_serial=$realtime;
        end
    end
    // 每个串行半周期后采样。时钟通道1111100000的下降边沿定位D0。
    always @(serial_clk)begin
        #0.2;
        if(ready)begin
            if({cn,dn}!==~{cp,dp})begin $display("FAIL differential polarity");$finish;end
            if(previous_clock && !cp)begin aligned=1;bit_count=0;end
            if(aligned)begin
                for(i=0;i<3;i=i+1)serial_word[i][bit_count]=dp[i];
                serial_word[3][bit_count]=cp;
                if(bit_count==9)begin
                    actual={serial_word[3],serial_word[2],serial_word[1],serial_word[0]};
                    if(serial_word[3]!==10'b1111100000)begin $display("FAIL clock serialization");$finish;end
                    // 原语有固定内部流水；首次搜索对齐，之后必须逐字连续，不能重排/丢字。
                    if(last_match<0)begin
                        match_index=-1;match_count=0;
                        for(i=0;i<pixel_count;i=i+1)if(actual===expected_words[i])begin
                            match_index=i;match_count=match_count+1;
                        end
                        if(match_count==1)last_match=match_index;
                    end else begin
                        last_match=last_match+1;
                        if(last_match>=pixel_count || actual!==expected_words[last_match])begin
                            $display("FAIL serialized word got=%h expected=%h index=%0d",actual,expected_words[last_match],last_match);$finish;end
                        matched=matched+1;
                    end
                    serial_count=serial_count+1;
                end
                bit_count=(bit_count+1)%10;
            end
            previous_clock=cp;
        end else begin aligned=0;previous_clock=0;bit_count=0;end
    end
    integer j;
    initial begin
        #105;rst=1;wait(ready);
        repeat(15)@(negedge pixel_clk);
        for(j=0;j<700;j=j+1)begin
            @(negedge pixel_clk);de=(j%32<25);ctr=j%4;rgb={j[7:0],~j[7:0],j[7:0]^8'h5a};
        end
        repeat(15)@(negedge pixel_clk);
        if(matched<650)begin $display("FAIL insufficient PHY checks %0d",matched);$finish;end
        rst=0;#1;if(ready!==0)begin $display("FAIL guard reset");$finish;end
        $display("PASS tb_hdmi_phy: vendor PLL 49/245MHz, 4 OSER10 lanes, LSB order, RGB/control alignment (%0d)",matched);$finish;
    end
    initial begin #200000;$display("FAIL PHY timeout");$finish;end
endmodule
