`timescale 1ns/1ps
// 使用正式模态音频，而非人造正弦/锯齿，验证双画面与真实波形副本。
module tb_final_display_frame;
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
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),
        .H_FRONT(40),.H_SYNC(104),.H_BACK(144),.V_FRONT(3),.V_SYNC(7),.V_BACK(14),
        .HS_ACTIVE(0),.VS_ACTIVE(1)) dut(.sys_clk(clk),.pixel_clk(pclk),.rst_n(rst),
        .key_down(held),.piano_keys(piano_held),.guitar_keys(guitar_held),.volume(7'd96),
        .pitch_bend(16'sd0),.octave(2'd1),.sustain(1'b0),.instrument_guitar(mode),
        .audio_valid(audio_valid),.audio_sample(audio_sample),.lcd_rgb(rgb),.lcd_de(de),
        .lcd_hsync(hs),.lcd_vsync(vs),.frame_start(fs),.display_sample_drop(drop));
    integer x=0,y=0,frames=0,active=0,wave_pixels=0,wave_min_y=600,wave_max_y=0;
    integer fd=0,gfd=0,note_marks=0,column,row,glyph,pixels=0;
    reg tracking=0,ink;
    reg [575:0] reference[0:63];
    always @(posedge pclk)begin
        #1;
        if(fs)begin
            if(tracking && (x!=1311 || y!=623 || active!=614400))begin $display("FAIL final CVT frame length");$finish;end
            frames=frames+1;x=0;y=0;active=0;tracking=1;
            if(frames==4)begin
                $fclose(fd);$fclose(gfd);
                if(wave_pixels<1000 || wave_max_y-wave_min_y<48 || note_marks<200)begin
                    $display("FAIL final weak/empty display wave=%0d span=%0d marks=%0d",wave_pixels,wave_max_y-wave_min_y,note_marks);$finish;end
                $display("PASS tb_final_display_frame: piano/guitar real modal frames, waveform pixels=%0d span=%0d, fret markers=%0d, frame-atomic state",wave_pixels,wave_max_y-wave_min_y,note_marks);$finish;
            end
        end else if(tracking)begin if(x==1311)begin x=0;y=y+1;end else x=x+1;end
        if(tracking)begin
            if(de!==(x<1024 && y<600) || hs!==!(x>=1064 && x<1168) || vs!==(y>=603 && y<610))begin
                $display("FAIL final HDMI timings x=%0d y=%0d",x,y);$finish;end
            if((^rgb)===1'bx || (!de && rgb!==0))begin $display("FAIL final undefined/blank pixel");$finish;end
            if(de)begin
                active=active+1;
                if(frames==2)$fdisplay(fd,"%06x",rgb);
                if(frames==3)$fdisplay(gfd,"%06x",rgb);
                if(frames==2 && x>=48 && x<816 && y>=216 && y<352 && rgb==24'h65d9ed)begin
                    wave_pixels=wave_pixels+1;if(y<wave_min_y)wave_min_y=y;if(y>wave_max_y)wave_max_y=y;
                end
                if(frames==3 && x>=96 && x<928 && y>=404 && y<550 && rgb==24'hf0b76b)note_marks=note_marks+1;
                if((frames==2 || frames==3) && x>=40 && x<248 && y>=20 && y<68)begin
                    column=((x-40)/2)%26;row=(y-20)/2;glyph=(x-40)/52+1;
                    if(frames==3 && glyph>=3)glyph=glyph+2;
                    ink=(column<24)?reference[glyph][575-row*24-column]:1'b0;
                    if(rgb!==(ink?24'he8edf2:(frames==2?24'h0c141e:24'h18130f)))begin
                        $display("FAIL final Chinese title alignment x=%0d y=%0d",x,y);$finish;end
                end
                if(frames==2 && x==90 && y==510 && rgb!==24'h9fe4ee)begin $display("FAIL piano held key/mode atomicity");$finish;end
                if(frames==3 && x==640 && y==416 && rgb!==24'hf0b76b)begin $display("FAIL guitar C5 fret mapping");$finish;end
                if(frames==3 && x==448 && y==464 && rgb==24'hf0b76b)begin $display("FAIL old piano note shown as guitar");$finish;end
            end
        end
    end
    initial begin
        fd=$fopen("build/regression/final/piano_frame.hex","w");gfd=$fopen("build/regression/final/guitar_frame.hex","w");
        $readmemh("verification/data/display_ui_font_golden.mem",reference);
        #103;rst=1;repeat(20)@(negedge clk);kv=1;@(negedge clk);kv=0;
        keys[0]=0;keys[4]=0;keys[7]=0;
        wait(frames==2 && y==200);@(negedge clk);board_keys[1]=0;
        repeat(40)@(negedge clk);board_keys[1]=1;keys[12]=0;
    end
    initial begin #60000000;$display("FAIL final display timeout");$finish;end
endmodule
