`timescale 1ns/1ps
// 对照固定Git原版，逐拍比较真实RGB、同步、帧快照及显示丢样；不修改既有TB。
module tb_frame_display_equivalence;
    reg clk=0,pclk=0,run_pixel=1,rst_n=0;
    reg [6:0] volume=96,brightness=64;
    reg signed [15:0] bend=-16384;
    reg guitar=0,sustain=0;
    reg [1:0] octave=1;
    reg [12:0] keys=13'h091;
    reg valid=0;
    reg [10:0] divider=0;
    reg signed [15:0] sample=0;
    always #10 clk=~clk;
    always #10.204082 if(run_pixel)pclk=~pclk;
    always @(posedge clk)begin
        valid<=0;
        if(divider==1041)begin
            divider<=0;valid<=1;sample<=sample+16'sd211;
        end else divider<=divider+1'b1;
    end
    wire [23:0] rgb,old_rgb;
    wire de,hs,vs,fs,drop,old_de,old_hs,old_vs,old_fs,old_drop;
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),
        .TOUCH_PANEL(1),.BRIGHTNESS_PANEL(1),.H_FRONT(40),.H_SYNC(104),.H_BACK(144),
        .V_FRONT(3),.V_SYNC(7),.V_BACK(14)) dut(
        .sys_clk(clk),.pixel_clk(pclk),.rst_n(rst_n),.key_down(keys),
        .piano_keys(guitar?13'd0:keys),.guitar_keys(guitar?keys:13'd0),
        .volume(volume),.pitch_bend(bend),.octave(octave),.sustain(sustain),
        .instrument_guitar(guitar),.brightness(brightness),.touch_available(1'b1),
        .guide_valid(1'b0),.guide_index(4'd0),.guide_progress(4'd0),
        .audio_valid(valid),.audio_sample(sample),.lcd_rgb(rgb),.lcd_de(de),
        .lcd_hsync(hs),.lcd_vsync(vs),.frame_start(fs),.display_sample_drop(drop));
    instrument_display_reference #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),
        .TOUCH_PANEL(1),.BRIGHTNESS_PANEL(1),.H_FRONT(40),.H_SYNC(104),.H_BACK(144),
        .V_FRONT(3),.V_SYNC(7),.V_BACK(14)) reference(
        .sys_clk(clk),.pixel_clk(pclk),.rst_n(rst_n),.key_down(keys),
        .piano_keys(guitar?13'd0:keys),.guitar_keys(guitar?keys:13'd0),
        .volume(volume),.pitch_bend(bend),.octave(octave),.sustain(sustain),
        .instrument_guitar(guitar),.brightness(brightness),.touch_available(1'b1),
        .guide_valid(1'b0),.guide_index(4'd0),.guide_progress(4'd0),
        .audio_valid(valid),.audio_sample(sample),.lcd_rgb(old_rgb),.lcd_de(old_de),
        .lcd_hsync(old_hs),.lcd_vsync(old_vs),.frame_start(old_fs),.display_sample_drop(old_drop));
    integer cycles=0,commits=0,piano_pixels=0,guitar_pixels=0;
    always @(posedge pclk)begin
        if(dut.pixel_rst_n && dut.commit)commits=commits+1;
        #1;
        if(rst_n)begin
            cycles=cycles+1;
            if({rgb,de,hs,vs,fs,drop}!=={old_rgb,old_de,old_hs,old_vs,old_fs,old_drop})begin
                $display("FAIL display pixel/sync cycle=%0d new=%h old=%h",cycles,rgb,old_rgb);$stop;
            end
            if(dut.state_frame!==reference.state_frame ||
               dut.g_panel.u_renderer.bend_digits!==reference.g_panel.u_renderer.bend_digits)begin
                $display("FAIL display frame digits cycle=%0d commits=%0d new=%h old=%h",cycles,commits,
                         dut.g_panel.u_renderer.bend_digits,reference.g_panel.u_renderer.bend_digits);$stop;
            end
            if(de)begin
                if(dut.state_frame[39])guitar_pixels=guitar_pixels+1;
                else piano_pixels=piano_pixels+1;
            end
        end
    end
    initial begin
        #1;rst_n=1;#1;rst_n=0;
        repeat(8)@(negedge clk);rst_n=1;
        wait(commits==1);
        @(negedge clk);guitar=1;bend=16'sh8000;volume=127;brightness=1;octave=2;keys=13'h1555;sustain=1;
        wait(commits==2);
        @(negedge clk);bend=16'sh7fff;volume=1;brightness=127;octave=0;keys=13'h0222;
        wait(commits==3);repeat(8)@(negedge pclk);
        if(piano_pixels<614400 || guitar_pixels<614400)begin
            $display("FAIL display coverage piano=%0d guitar=%0d",piano_pixels,guitar_pixels);$stop;
        end
        @(negedge pclk);run_pixel=0;#3;rst_n=0;#1;
        if(rgb!==0 || de!==0 || dut.g_panel.u_renderer.bend_digits!==0)begin
            $display("FAIL display stopped-clock reset");$stop;
        end
        #100;run_pixel=1;repeat(8)@(negedge clk);rst_n=1;repeat(100)@(negedge pclk);
        $display("PASS tb_frame_display_equivalence: cycles=%0d piano_pixels=%0d guitar_pixels=%0d; RGB/sync/CDC/format frame-atomic, clock-stop reset/restart",cycles,piano_pixels,guitar_pixels);
        $finish;
    end
    initial begin #60000000;$display("FAIL display equivalence timeout");$stop;end
endmodule
