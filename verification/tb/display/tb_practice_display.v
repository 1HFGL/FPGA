`timescale 1ns/1ps
// 真实像素流水线/字模/CDC，输出两帧用于视觉检查，并独立核对边框颜色。
module tb_practice_display;
    reg clk=0,pclk=0,rst_n=0,guitar=0;
    reg [3:0] index=7,progress=3;
    wire [23:0] rgb;
    wire de,fs;
    always #10 clk=~clk;
    always #10.204082 pclk=~pclk;
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),.ENABLE_GUIDE(1),
        .H_FRONT(40),.H_SYNC(104),.H_BACK(144),.V_FRONT(3),.V_SYNC(7),.V_BACK(14),.HS_ACTIVE(0),.VS_ACTIVE(1)) dut(
        .sys_clk(clk),.pixel_clk(pclk),.rst_n(rst_n),.key_down(13'h4),.piano_keys(13'h4),.guitar_keys(13'h4),
        .volume(7'd100),.pitch_bend(16'd0),.octave(2'd1),.sustain(1'b0),.instrument_guitar(guitar),
        .brightness(7'd127),.touch_available(1'b0),.audio_valid(1'b0),.audio_sample(16'd0),
        .guide_valid(1'b1),.guide_index(index),.guide_progress(progress),
        .lcd_rgb(rgb),.lcd_de(de),.lcd_hsync(),.lcd_vsync(),.frame_start(fs),.display_sample_drop());
    integer frame=0,x=0,y=0,fd0,fd1,pixels=0,checks=0;
    reg [82:0] snapshot;
    reg tracking=0;
    always @(posedge pclk)begin
        #1;
        if(fs)begin
            frame=frame+1;x=0;y=0;tracking=1;snapshot=dut.state_frame;
            if(frame==4)begin
                $fclose(fd0);$fclose(fd1);
                if(pixels!=1228800 || checks!=5)begin $display("FAIL guide display coverage %0d/%0d",pixels,checks);$stop;end
                $display("PASS tb_practice_display: two full actual RGB frames; guide borders/ordinary held highlight/progress; atomic 83bit CDC");$finish;
            end
        end else if(tracking)begin if(x==1311)begin x=0;y=y+1;end else x=x+1;end
        if(tracking && frame>=2 && frame<=3 && de)begin
            if((^rgb)===1'bx || dut.state_frame!==snapshot)begin $display("FAIL guide undefined/tearing frame");$stop;end
            if(frame==2)$fdisplay(fd0,"%06x",rgb);else $fdisplay(fd1,"%06x",rgb);
            pixels=pixels+1;
            if(frame==2 && x==512 && y==500)begin
                if(rgb!==24'h397e75)begin $display("FAIL guide piano target border %h",rgb);$stop;end checks=checks+1;
            end
            if(frame==2 && x==200 && y==510)begin
                if(rgb!==24'hfaf2c6)begin $display("FAIL guide replaced ordinary held color %h",rgb);$stop;end checks=checks+1;
            end
            if(frame==2 && x==483 && y==40)begin
                if(rgb!==24'hf8f7f3)begin $display("FAIL guide separator modulo artifact %h",rgb);$stop;end checks=checks+1;
            end
            if(frame==2 && x==490 && y==49)begin
                if(rgb!==24'h686e70)begin $display("FAIL guide separator diagonal %h",rgb);$stop;end checks=checks+1;
            end
            if(frame==3 && x==698 && y==550)begin
                if(rgb!==24'h397e75)begin $display("FAIL guide guitar target border %h",rgb);$stop;end checks=checks+1;
            end
        end
    end
    initial begin
        fd0=$fopen("build/regression/final/guide_piano.hex","w");
        fd1=$fopen("build/regression/final/guide_guitar.hex","w");
        if(fd0==0 || fd1==0)begin $display("FAIL guide output directory");$stop;end
        #103;rst_n=1;
        wait(frame==2 && y==100);@(negedge clk);guitar=1;index=9;progress=5;
    end
    initial begin #70000000;$display("FAIL guide display timeout");$stop;end
endmodule
