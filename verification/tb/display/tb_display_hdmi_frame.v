`timescale 1ns/1ps
module tb_display_hdmi_frame;
    reg sys_clk=0,pclk=0,rst=0;
    reg [12:0] keys=13'h091;
    reg guitar=0;
    reg sample_valid=0;
    reg signed [15:0] sample=0;
    integer sample_div=0;
    // 约48kHz测试锯齿，仅验证波形窗口；不是钢琴录音。
    always @(posedge sys_clk) begin
        sample_valid<=0;
        if(!rst)begin sample_div<=0;sample<=0;end
        else if(sample_div==1041)begin sample_div<=0;sample_valid<=1;sample<=sample+16'sd512;end
        else sample_div<=sample_div+1;
    end
    wire [23:0] rgb;
    wire de,hs,vs,fs;
    always #10 sys_clk=~sys_clk;
    always #10.204082 pclk=~pclk;
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),
        .H_FRONT(40),.H_SYNC(104),.H_BACK(144),.V_FRONT(3),.V_SYNC(7),.V_BACK(14),
        .HS_ACTIVE(0),.VS_ACTIVE(1),.WAVE_GAIN_SHIFT(0)) dut(.sys_clk(sys_clk),.pixel_clk(pclk),.rst_n(rst),
        .key_down(keys),.volume(7'd96),.pitch_bend(16'sd8192),.octave(2'd1),.sustain(1'b0),
        .instrument_guitar(guitar),.audio_valid(sample_valid),.audio_sample(sample),
        .lcd_rgb(rgb),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.frame_start(fs),.display_sample_drop());
    integer x=0,y=0,frames=0,active=0,lit=0,wave_pixels=0,fd=0,guitar_fd=0;
    reg tracking=0;
    reg [1023:0] filename;
    reg [575:0] glyph_reference[0:63];
    reg expected_ink;
    integer title_column,title_row,title_glyph;
    always @(posedge pclk)begin
        #1;
        if(fs)begin
            if(tracking && (x!=1311 || y!=623 || active!=614400))begin $display("FAIL HDMI frame totals");$finish;end
            frames=frames+1;x=0;y=0;active=0;tracking=1;
            if(frames==4)begin
                if(fd)$fclose(fd);
                if(guitar_fd)$fclose(guitar_fd);
                if(lit<10000)begin $display("FAIL empty HDMI UI");$finish;end
                if(wave_pixels!=1024)begin $display("FAIL waveform pixels %0d",wave_pixels);$finish;end
                $display("PASS tb_display_hdmi_frame: native 1024x600 UI, CVT sync, Chinese title, waveform, frame-atomic keys");$finish;
            end
        end else if(tracking)begin
            if(x==1311)begin x=0;y=y+1;end else x=x+1;
        end
        if(tracking)begin
            if(de!==(x<1024 && y<600) || hs!==!(x>=1064 && x<1168) || vs!==(y>=603 && y<610))begin
                $display("FAIL HDMI timing x=%0d y=%0d",x,y);$finish;end
            if((^rgb)===1'bx)begin $display("FAIL HDMI unknown RGB");$finish;end
            if(!de && rgb!==0)begin
                $display("FAIL HDMI blanking x=%0d y=%0d",x,y);$finish;end
            if(de && (x==0 || x==1023 || y==0 || y==599) && rgb!==24'h101619)begin
                $display("FAIL HDMI native canvas edge x=%0d y=%0d",x,y);$finish;end
            if(de)begin
                active=active+1;
                if(frames==2)begin if(fd)$fdisplay(fd,"%06x",rgb);if(rgb!=0)lit=lit+1;end
                if(frames==3 && guitar_fd)$fdisplay(guitar_fd,"%06x",rgb);
                // 用整字参考逐像素核对2倍标题，覆盖同步ROM、列寻址和输出流水线对齐。
                if((frames==2 || frames==3) && x>=40 && x<248 && y>=16 && y<64)begin
                    title_column=((x-40)/2)%26;title_row=(y-16)/2;title_glyph=(x-40)/52+1;
                    if(frames==3 && title_glyph>=3)title_glyph=title_glyph+2;
                    expected_ink=(title_column<24)?glyph_reference[title_glyph][575-title_row*24-title_column]:1'b0;
                    if(rgb!==(expected_ink?24'he7ecef:24'h101619))begin
                        $display("FAIL scaled title x=%0d y=%0d",x,y);$finish;end
                end
                if(frames==2 && x>=256 && x<768 && y>=208 && y<328 && rgb==24'h5bd6bb)
                    wave_pixels=wave_pixels+1;
            end
            if(frames==2 && x==80 && y==500 && rgb!==24'ha8decf)begin
                $display("FAIL HDMI key snapshot/offset");$finish;end
            if(frames==3 && x==80 && y==500 && rgb!==24'hf0ede5)begin
                $display("FAIL HDMI next frame key release");$finish;end
        end
    end
    initial begin
        $readmemh("verification/data/display_font_golden.mem",glyph_reference);
        if($value$plusargs("FRAME=%s",filename))fd=$fopen(filename,"w");
        if($value$plusargs("GUITAR_FRAME=%s",filename))guitar_fd=$fopen(filename,"w");
        #103;rst=1;
        wait(frames==2 && y==200);@(negedge sys_clk);keys=0;guitar=1;
    end
    initial begin #60000000;$display("FAIL HDMI frame timeout");$finish;end
endmodule
