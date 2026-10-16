`timescale 1ns/1ps
// 这是仿真接入外壳，不是有引脚/PLL约束的屏幕板级工程。
// 两个真实钢琴实例输入完全相同，仅DUT音频/状态的副本连接显示。
// 显示停钟和共同复位只作用于显示，不能成为音频等待条件。
module tb_music_display_isolation;
    reg clk=0,pixel_clk=0,rst_n=0,display_rst_n=0,pixel_run=1;
    reg [1:0] keys=2'b11;
    always #10 clk=~clk;
    always #15 begin
        if(pixel_run) pixel_clk=~pixel_clk;
        else pixel_clk=0;
    end
    wire tx0,bck0,ws0,din0,pa0,tx1,bck1,ws1,din1,pa1;
    wire [23:0] rgb;
    wire de,hs,vs,display_frame,drop;
    integer cycles=0,samples=0,words=0,bits=0,nonzero_words=0;
    integer request_at=0,frame_count=0,pixel_samples=0,visible_pixels=0,drops=0;
    integer stage=0,stage_samples[0:3],stage_words[0:3],i;
    integer normal_pixel_samples=0,stopped_drops=0,reset_audio_samples=0;
    integer samples_before=0,drops_before=0,pixels_before=0;
    reg [15:0] serial=0,pending=0,expected_word=0;
    reg pending_valid=0;

    music_uart_top reference_audio(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(keys),.uart_rx(1'b1),.uart_tx(tx0),
        .HP_BCK(bck0),.HP_WS(ws0),.HP_DIN(din0),.PA_EN(pa0));
    music_display_top dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(keys),.uart_rx(1'b1),.uart_tx(tx1),
        .HP_BCK(bck1),.HP_WS(ws1),.HP_DIN(din1),.PA_EN(pa1),
        .pixel_clk(pixel_clk),.display_rst_n(display_rst_n),.lcd_rgb(rgb),.lcd_de(de),
        .lcd_hsync(hs),.lcd_vsync(vs),.frame_start(display_frame),.display_sample_drop(drop));

    // 每拍比较而不只是最终checksum：相同样本迟一拍也会失败。
    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst_n && dut.u_core.audio_ready!==reference_audio.u_core.audio_ready) begin
            $display("FAIL display affected audio reset/ready stage=%0d cycle=%0d",stage,cycles); $finish;
        end
        if(rst_n && dut.u_core.audio_ready) begin
            if({dut.u_core.sample_request,dut.u_core.sample_valid,dut.u_core.sample_data,
                dut.u_core.sample_underrun,dut.u_core.voice_gate,dut.u_core.voice_count} !==
               {reference_audio.u_core.sample_request,reference_audio.u_core.sample_valid,
                reference_audio.u_core.sample_data,reference_audio.u_core.sample_underrun,
                reference_audio.u_core.voice_gate,reference_audio.u_core.voice_count}) begin
                $display("FAIL display affected audio internal sequence/deadline stage=%0d cycle=%0d",stage,cycles); $finish;
            end
            if({tx0,bck0,ws0,din0,pa0}!=={tx1,bck1,ws1,din1,pa1}) begin
                $display("FAIL display affected board audio outputs stage=%0d cycle=%0d",stage,cycles); $finish;
            end
            if(dut.u_core.sample_request) request_at=cycles;
            // 帧消费在sample_valid之前：同拍输入按合同属于下一缓存。
            if(dut.u_core.u_b.frame_start) begin
                expected_word=pending_valid ? pending : 16'd0;
                pending_valid=0;
                frame_count=frame_count+1;
            end
            if(dut.u_core.sample_valid) begin
                if(cycles-request_at!=924 || dut.u_core.sample_clipped!==0) begin
                    $display("FAIL display isolation R924/clipping stage=%0d",stage); $finish;
                end
                pending=dut.u_core.sample_data; pending_valid=1;
                samples=samples+1; stage_samples[stage]=stage_samples[stage]+1;
            end
            if(drop) drops=drops+1;
        end
    end
    // 在DAC真正采样沿还原完整字；端口逐拍等价不能替代样本合同。
    always @(posedge bck1) begin
        if(rst_n && dut.u_core.audio_ready) begin
            if(ws1!==(words%2) || dut.u_core.sample_underrun!==(words<2)) begin
                $display("FAIL isolation serial channel/underrun"); $finish;
            end
            serial={serial[14:0],din1}; bits=bits+1;
            if(bits==16) begin
                if(serial!==expected_word) begin
                    $display("FAIL isolation word mismatch stage=%0d word=%0d expected=%h actual=%h",stage,words,expected_word,serial); $finish;
                end
                if(serial!=0) nonzero_words=nonzero_words+1;
                words=words+1; bits=0; stage_words[stage]=stage_words[stage]+1;
            end
        end
    end
    always @(posedge pixel_clk) begin
        if(display_rst_n && dut.u_display.pixel_rst_n) begin
            if(dut.u_display.sample_pixel_valid) pixel_samples=pixel_samples+1;
            if(de && rgb!=0) visible_pixels=visible_pixels+1;
            if(display_frame) normal_pixel_samples=normal_pixel_samples+1;
        end
    end

    initial begin
        for(i=0;i<4;i=i+1) begin stage_samples[i]=0; stage_words[i]=0; end
        #77; rst_n=1; display_rst_n=1;
        #100003; keys=2'b10;
        #6000000; keys=2'b00; // 保持实际2ms消抖和原钢琴ADSR。
        #13000000;
        if(nonzero_words<100 || pixel_samples<256 || visible_pixels<10000 ||
           normal_pixel_samples<2 || dut.u_display.wave_ready!==1) begin
            $display("FAIL display normal-load coverage words=%0d received=%0d pixels=%0d frames=%0d wave=%b",nonzero_words,pixel_samples,visible_pixels,normal_pixel_samples,dut.u_display.wave_ready); $finish;
        end
        @(negedge pixel_clk); pixel_run=0; stage=1;
        samples_before=samples; drops_before=drops; pixels_before=pixel_samples;
        #2000000; keys=2'b01; // 像素停钟时仍必须处理实体松键/保持音。
        #2000000;
        if(samples-samples_before<190 || drops-drops_before<180 || pixel_samples!=pixels_before) begin
            $display("FAIL stopped-pixel coverage samples=%0d drops=%0d",samples-samples_before,drops-drops_before); $finish;
        end
        stopped_drops=drops-drops_before;
        // 显示共同复位在pixel_clk停止时异步断言，音频复位保持高。
        stage=2; display_rst_n=0; samples_before=samples;
        #1000000;
        if(samples-samples_before<47 || dut.u_display.sys_rst_n!==0 || dut.u_display.pixel_rst_n!==0) begin
            $display("FAIL display reset blocked audio/failed reset"); $finish;
        end
        reset_audio_samples=samples-samples_before;
        display_rst_n=1; #103;
        if(dut.u_display.pixel_rst_n!==0) begin $display("FAIL pixel reset released without clock"); $finish; end
        stage=3; pixel_run=1; pixels_before=pixel_samples;
        #18000000;
        if(pixel_samples-pixels_before<256 || dut.u_display.wave_ready!==1) begin
            $display("FAIL display did not resume"); $finish;
        end
        for(i=0;i<4;i=i+1) begin
            if(stage_samples[i]<40 || stage_words[i]<80) begin $display("FAIL insufficient isolation stage=%0d",i); $finish; end
        end
        $display("PASS tb_music_display_isolation: actual default-debounce piano, %0d R924 samples, %0d DAC words, stopped-pixel drops=%0d reset-stage samples=%0d; display-only copy/no feedback",samples,words,stopped_drops,reset_audio_samples);
        $finish;
    end
    initial begin #50000000; $display("FAIL display isolation timeout"); $finish; end
endmodule
