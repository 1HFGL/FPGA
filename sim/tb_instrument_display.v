`timescale 1ns/1ps
module tb_instrument_display;
    reg sys_clk=0,pixel_clk=0,rst_n=0;
    reg [12:0] keys=13'h091; // C/E/G
    reg [6:0] volume=96;
    reg signed [15:0] bend=0;
    reg [1:0] octave=1;
    reg sustain=0,guitar=0,audio_valid=0;
    reg signed [15:0] sample=0;
    wire [23:0] rgb;
    wire de,hs,vs,fs,drop;
    always #10 sys_clk=~sys_clk;
    always #15 pixel_clk=~pixel_clk; // 仿真用33.333MHz，非最终屏幕PLL配置
    instrument_display #(.WAVE_GAIN_SHIFT(0)) dut(.sys_clk(sys_clk),.pixel_clk(pixel_clk),.rst_n(rst_n),
        .key_down(keys),.volume(volume),.pitch_bend(bend),.octave(octave),.sustain(sustain),
        .instrument_guitar(guitar),.audio_valid(audio_valid),.audio_sample(sample),
        .lcd_rgb(rgb),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.frame_start(fs),.display_sample_drop(drop));
    integer div=0,phase=0,frames=0,px=0,py=0,active_pixels=0,drops=0;
    integer fd1=0,fd2=0;
    reg tracking=0;
    reg [1023:0] preview1,preview2;
    reg [23:0] expected_key;
    always @(negedge sys_clk) begin
        audio_valid=0;
        if(rst_n) begin
            if(div==1041) begin
                div=0;audio_valid=1;sample={phase[7:0],8'd0};phase=(phase+8)&255;
            end else div=div+1;
        end else begin div=0;phase=0;sample=0;end
    end
    always @(posedge sys_clk) if(drop) drops=drops+1;
    always @(posedge pixel_clk) begin
        #1;
        if(rst_n) begin
            if(fs) begin
                if(tracking && (px!=1055 || py!=524 || active_pixels!=384000)) begin
                    $display("FAIL frame totals x=%0d y=%0d active=%0d",px,py,active_pixels);$finish;
                end
                frames=frames+1;tracking=1;px=0;py=0;active_pixels=0;
                if(frames==4) begin
                    if(fd1) $fclose(fd1);
                    if(fd2) $fclose(fd2);
                    if(drops!=0) begin $display("FAIL display dropped %0d nominal-rate samples",drops);$finish;end
                    $display("PASS tb_instrument_display: full RGB frames, atomic status, 48k capture, blanking, alignment");$finish;
                end
            end else if(tracking) begin
                if(px==1055) begin px=0;py=py+1;end else px=px+1;
            end
            if(tracking) begin
                if(de!==(px<800 && py<480) || hs!==!(px>=840 && px<968) || vs!==!(py>=493 && py<495)) begin
                    $display("FAIL RGB timing alignment frame=%0d x=%0d y=%0d",frames,px,py);$finish;
                end
                if((^rgb)===1'bx || (!de && rgb!==0)) begin $display("FAIL RGB unknown/blank");$finish;end
                if(de) begin
                    active_pixels=active_pixels+1;
                    if(frames==2 && fd1) $fdisplay(fd1,"%06x",rgb);
                    if(frames==3 && fd2) $fdisplay(fd2,"%06x",rgb);
                end
                if(px==80 && py==410) begin
                    expected_key=(frames==2) ? 24'h35dfb2 : 24'he7edf5;
                    if(rgb!==expected_key) begin $display("FAIL status snapshot/key frame=%0d",frames);$finish;end
                end
                if(px==100 && py==13 && frames>=2) begin
                    if((frames==2 && rgb!==24'he1eaf5) || (frames==3 && rgb!==24'h0b1220)) begin
                        $display("FAIL piano/guitar frame snapshot");$finish;
                    end
                end
                if(px==200 && py==196 && frames>=2 && !dut.u_wave.wave_ready) begin
                    $display("FAIL wave page did not publish");$finish;
                end
            end
        end
    end
    initial begin
        if($value$plusargs("PIANO_FRAME=%s",preview1)) fd1=$fopen(preview1,"w");
        if($value$plusargs("GUITAR_FRAME=%s",preview2)) fd2=$fopen(preview2,"w");
        #103;rst_n=1;
        wait(frames==2 && py==200);
        @(negedge sys_clk);keys=13'h244;guitar=1;sustain=1;volume=127;bend=-32768;octave=2;
        // 改在帧中部，第二帧余下像素必须仍显示钢琴/C和弦，第三帧才一起更新。
    end
    initial begin #60000000;$display("FAIL display timeout");$finish;end
endmodule
