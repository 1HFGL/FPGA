// 本轮独立验收：由既有完整帧测试的时序/管线检查扩展，原TB保持原样。
`timescale 1ns/1ps
// 新 1024x600 “静奏”界面：检查真实 RTL 输出的一帧可复现、分层文字有覆盖度、
// 乐器主体与持键映射正确，并与绘制器请求逐像素一致。
// 不修改旧 tb_final_display_frame；两者使用同一 instrument_display，仅 UI 参数不同。
module tb_simple_display_frames;
    reg clk=0,pclk=0,rst=0;
    reg [12:0] keys=13'h1fff;
    reg [1:0] board_keys=3;
    reg kv=0;
    always #10 clk=~clk;
    always #10.204082 pclk=~pclk;
    wire audio_valid,mode;
    wire signed [15:0] audio_sample;
    wire [12:0] held,piano_held,guitar_held;
    instrument_uart_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.VOICES(16),.ENABLE_CONTROLS(1),
        .ENABLE_GUITAR(1),.USE_MODAL(1),.EXTERNAL_PIANO_KEYS(1),.REQUEST_LEAD_HALF_EDGES(60),
        .DEBOUNCE_CYCLES(8)) core(.sys_clk(clk),.sys_rst_n(rst),.Key_in(board_keys),.piano_key_n(keys),
        .uart_rx(1'b1),.uart_tx(),.HP_BCK(),.HP_WS(),.HP_DIN(),.PA_EN(),
        .knob_value_flat({7'd64,7'd96}),.knob_valid(kv),.param_ready(1'b1),.param_fault(1'b0),
        .control_sustain(1'b0),.control_octave(2'd1),.control_ready(),
        .monitor_audio_valid(audio_valid),.monitor_audio_sample(audio_sample),
        .monitor_key_down(held),.monitor_piano_keys(piano_held),.monitor_guitar_keys(guitar_held),
        .monitor_instrument_guitar(mode));
    wire [23:0] rgb;wire de,hs,vs,fs,drop;
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),
        .H_FRONT(40),.H_SYNC(104),.H_BACK(144),.V_FRONT(3),.V_SYNC(7),.V_BACK(14),
        .HS_ACTIVE(0),.VS_ACTIVE(1)) dut(.sys_clk(clk),.pixel_clk(pclk),.rst_n(rst),
        .key_down(held),.piano_keys(piano_held),.guitar_keys(guitar_held),.volume(7'd96),
        .pitch_bend(16'sd0),.octave(2'd1),.sustain(1'b0),.instrument_guitar(mode),
        .audio_valid(audio_valid),.audio_sample(audio_sample),.lcd_rgb(rgb),.lcd_de(de),
        .lcd_hsync(hs),.lcd_vsync(vs),.frame_start(fs),.display_sample_drop(drop));
    integer x=0,y=0,frames=0,active=0,wave_pixels=0,wave_min_y=600,wave_max_y=0;
    integer fd=0,gfd=0,gold=0,title_marks=0,soft_edges=0,piano_marks=0;
    reg tracking=0;
    // lcd_rgb 是寄存输出，比较的是“上一拍组合期望值”，因此多存一拍。
    reg [23:0] expected_prev;
    reg expected_valid;
    always @(posedge pclk) begin
        #1;
        if(fs)begin
            if(tracking && (x!=1311 || y!=623 || active!=614400))begin
                $display("FAIL ui CVT frame length x=%0d y=%0d active=%0d",x,y,active);$finish;end
            frames=frames+1;x=0;y=0;active=0;tracking=1;
            if(frames==4)begin
                $fclose(fd);$fclose(gfd);
                // 新界面波形区约128像素、每列真实min/max轨迹：真实信号至少 1000 像素、
                // 纵向跨度 ≥40（波形幅度随实测采样变化，不硬编码旧画面高度）。
                if(wave_pixels<1000 || wave_max_y-wave_min_y<40)begin
                    $display("FAIL ui waveform weak pixels=%0d span=%0d",wave_pixels,wave_max_y-wave_min_y);$finish;end
                if(gold<400000)begin $display("FAIL ui renderer/pixel mismatch count=%0d",gold);$finish;end
                if(title_marks<400)begin $display("FAIL ui title too weak marks=%0d",title_marks);$finish;end
                if(soft_edges<40)begin $display("FAIL ui no coverage edges soft=%0d",soft_edges);$finish;end
                if(piano_marks<50)begin $display("FAIL ui piano held keys missing=%0d",piano_marks);$finish;end
                $display("PASS tb_simple_display_frames: both modes real modal frames, pixel-exact renderer match=%0d, title=%0d soft=%0d piano_held=%0d",
                    gold,title_marks,soft_edges,piano_marks);
                $finish;
            end
        end else if(tracking)begin if(x==1311)begin x=0;y=y+1;end else x=x+1;end
        if(tracking)begin
            if(de!==(x<1024 && y<600) || hs!==!(x>=1064 && x<1168) || vs!==(y>=603 && y<610))begin
                $display("FAIL ui HDMI timings x=%0d y=%0d",x,y);$finish;end
            if((^rgb)===1'bx || (!de && rgb!==0))begin $display("FAIL ui undefined/blank pixel x=%0d y=%0d",x,y);$finish;end
            if(de)begin
                active=active+1;
                if(x==0 && y==0 && rgb!==24'hecebe7)begin $display("FAIL warm background");$finish;end
                if(frames==2 && x==80 && y==520 && rgb!==24'hfaf2c6)begin
                    $display("FAIL piano C held body");$finish;end
                if(frames==3 && x==40 && y==542 && rgb!==24'hf5f4ef)begin
                    $display("FAIL guitar inherited piano held");$finish;end
                if(frames==3 && x==940 && y==542 && rgb!==24'hfaf2c6)begin
                    $display("FAIL guitar C5 pad");$finish;end
                if(frames==2)$fdisplay(fd,"%06x",rgb);
                if(frames==3)$fdisplay(gfd,"%06x",rgb);
                // 与绘制器逐像素核对：上拍组合值（底色/文字色/覆盖度）→ 本拍寄存输出。
                if(expected_valid && expected_prev!==rgb)begin
                    $display("FAIL ui mix mismatch x=%0d y=%0d rgb=%06x exp=%06x",x,y,rgb,expected_prev);$finish;
                end
                if(expected_valid) gold=gold+1;
                // 采样本拍 DUT 的组合请求，下一拍与寄存输出比较。
                if(dut.de_l1 && dut.ui_l1)begin
                    expected_valid=1'b1;
                    if(dut.cov==2'd3) expected_prev=dut.color_l1;
                    else if(dut.cov==2'd0) expected_prev=dut.base_l1;
                    else begin
                        expected_prev={dut.mix_r,dut.mix_g,dut.mix_b};
                        soft_edges=soft_edges+1;
                    end
                end else expected_valid=1'b0;
                // 标题区应当有多级覆盖度（不是 1bit 放大的块边）。
                if(frames==2 && x>=40 && x<248 && y>=16 && y<64)begin
                    if(dut.title_on_q) title_marks=title_marks+1;
                end
                // 钢琴持键：C4/E4/G4 白键应有高亮色。
                if(frames==2 && x>=32 && x<992 && y>=400 && y<568 &&
                   (rgb==24'hfaf2c6 || rgb==24'hf0de6b)) piano_marks=piano_marks+1;
                // 波形：拾取若干真实峰值像素的纵向跨度。
                if(frames==2 && x>=48 && x<816 && y>=208 && y<352 && rgb==24'hf0de6b)begin
                    wave_pixels=wave_pixels+1;if(y<wave_min_y)wave_min_y=y;if(y>wave_max_y)wave_max_y=y;
                end
            end
        end
    end
    initial begin
        fd=$fopen("build/regression/final/piano_simple_frame.hex","w");
        gfd=$fopen("build/regression/final/guitar_simple_frame.hex","w");
        #103;rst=1;repeat(20)@(negedge clk);kv=1;@(negedge clk);kv=0;
        keys[0]=0;keys[4]=0;keys[7]=0;
        wait(frames==2 && y==200);@(negedge clk);board_keys[1]=0;
        repeat(40)@(negedge clk);board_keys[1]=1;keys[12]=0;
    end
    initial begin #60000000;$display("FAIL ui display timeout");$finish;end
endmodule
