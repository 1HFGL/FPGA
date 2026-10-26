`timescale 1ns/1ps
// Actual display pipeline pixels, with deterministic monitor inputs for visual QA.
module tb_practice_frames;
    reg GUITAR=0;reg [1:0] OCTAVE=0;integer scene=0;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg [10:0] divider=0;
    reg valid=0;
    reg signed [15:0] sample=0;
    always @(posedge clk)begin
        valid<=0;
        if(divider==1041)begin
            divider<=0;valid<=1;
            sample<=(sample>=1024)?-16'sd1024:sample+16'sd128;
        end else divider<=divider+1'b1;
    end
    wire [23:0] rgb;
    wire de,fs;
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),
        .CONTROL_FEATURES(1),.TOUCH_PANEL(1),.BRIGHTNESS_PANEL(1),.ENABLE_GUIDE(0),.H_FRONT(40),.H_SYNC(104),.H_BACK(144),
        .V_FRONT(3),.V_SYNC(7),.V_BACK(14)) dut(
        .sys_clk(clk),.pixel_clk(clk),.rst_n(rst_n),.key_down(13'h091),
        .piano_keys(GUITAR?13'd0:13'h091),.guitar_keys(GUITAR?13'h091:13'd0),
        .volume(7'd96),.pitch_bend(16'sd0),.octave(OCTAVE),.sustain(1'b0),
        .instrument_guitar(GUITAR!=0),.brightness(7'd64),.touch_available(1'b1),
        .guide_status({12'd0,1'b0,1'b1,1'b0,2'd2,3'd2,8'd90,10'd17,37'h1110911001}),.guide_valid(1'b0),.guide_index(4'd0),.guide_progress(4'd0),
        .audio_valid(valid),.audio_sample(sample),.lcd_rgb(rgb),.lcd_de(de),
        .frame_start(fs));
    integer fd,frames=0,pixels=0;
    reg [1023:0] path;
    initial begin
        path="build/control_tests/practice_0.hex";
        fd=$fopen(path,"w");
        if(fd==0)begin $display("FAIL preview file");$finish;end
        repeat(8)@(negedge clk);rst_n=1;
    end
    always @(posedge clk)begin
        #1;
        if(fs)begin
            frames=frames+1;
            if(frames%3==1 && frames>1)begin
                $fclose(fd);
                if(pixels!=614400)begin $display("FAIL preview size %d",pixels);$finish;end
                pixels=0;scene=scene+1;
                if(scene==6)begin $display("PASS tb_practice_frames: six actual RGB frames / two instruments / three octaves");$finish;end
                GUITAR=scene>=3;OCTAVE=scene%3;
                case(scene)
                  1:path="build/control_tests/practice_1.hex";
                  2:path="build/control_tests/practice_2.hex";
                  3:path="build/control_tests/practice_3.hex";
                  4:path="build/control_tests/practice_4.hex";
                  5:path="build/control_tests/practice_5.hex";
                endcase
                fd=$fopen(path,"w");
            end
        end
        if(frames%3==0 && frames>0 && de)begin
            if(dut.state_frame[72:66]!==7'd64 || dut.meter_height<32)begin
                $display("FAIL preview brightness/meter not settled");$finish;
            end
            if((^rgb)===1'bx)begin $display("FAIL preview unknown RGB");$finish;end
            $fdisplay(fd,"%06x",rgb);pixels=pixels+1;
        end
    end
    initial begin #400000000;$display("FAIL preview timeout");$finish;end
endmodule
