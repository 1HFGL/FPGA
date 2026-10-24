`timescale 1ns/1ps
module tb_meter_scale;
    reg clk=0,rst_n=0,commit=0;
    reg [15:0] raw=0;
    wire [15:0] level,peak;
    wire [7:0] height,peak_height;
    integer n,old_height,frames;
`ifndef BASELINE
    reg [11:0] x=920,y=318;
    reg [3:0] wave_gain=0;
    reg [6:0] brightness=127;
    wire [23:0] rgb;
    instrument_panel_ui #(.LOG_METER(1),.SHOW_BRIGHTNESS(1)) panel(.x(x),.y(y),.key_down(13'd0),
        .volume(7'd64),.brightness(brightness),.touch_available(1'b0),.pitch_bend(16'sd0),
        .octave(2'd1),.sustain(1'b0),.instrument_guitar(1'b0),.guide_valid(1'b1),
        .guide_index(4'd0),.guide_progress(4'd0),.wave_ready(1'b0),
        .wave_min(16'sd0),.wave_max(16'sd0),.peak_level(raw),.gain_shift(wave_gain),
        .activity(39'd0),.meter_level(level),.meter_peak(peak),
        .meter_height(height),.meter_peak_height(peak_height),.base_rgb(rgb));
`endif
    always #10 clk=~clk;
    display_feedback dut(.pixel_clk(clk),.rst_n(rst_n),.frame_commit(commit),
        .held(13'd0),.instrument_guitar(1'b0),.raw_peak(raw),.activity(),
        .meter_level(level),.meter_peak(peak)
`ifndef BASELINE
        ,.meter_height(height),.meter_peak_height(peak_height)
`endif
    );
`ifdef BASELINE
    assign height=level[15:8];
    assign peak_height=peak[15:8];
`endif
    task frame;
        begin @(negedge clk);commit=1;@(negedge clk);commit=0;end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        raw=256;frame;
        if(height<32 || height>56)begin $display("FAIL quiet tone invisible height=%0d",height);$finish;end
`ifndef BASELINE
        #1;if(rgb!==24'hf0de6b)begin $display("FAIL quiet tone not drawn");$finish;end
        wave_gain=8;#1;
        if(rgb!==24'hf0de6b)begin $display("FAIL waveform gain changed meter");$finish;end
`endif
        raw=0;
        repeat(100)frame;
        if(height!=0 || peak_height!=0)begin $display("FAIL silence not zero");$finish;end
`ifndef BASELINE
        y=335;#1;if(rgb!==24'h424a4c)begin $display("FAIL fake meter at silence");$finish;end
`endif
        old_height=0;
        for(n=0;n<=32768;n=n+1)begin
            raw=n;frame;
            if(height<old_height || height>128)begin $display("FAIL scale monotonic/bound n=%0d",n);$finish;end
            if(level!==raw)begin $display("FAIL raw amplitude changed");$finish;end
            old_height=height;
        end
        if(height!=128 || peak_height!=128)begin $display("FAIL full scale");$finish;end
`ifndef BASELINE
        y=220;#1;if(rgb!==24'he18b77)begin $display("FAIL clipping color");$finish;end
`endif
        raw=0;frame;
        if(peak_height!=128)begin $display("FAIL peak hold");$finish;end
        frames=0;
        while((height!=0 || peak_height!=0) && frames<100)begin frame;frames=frames+1;end
        if(frames==100)begin $display("FAIL release did not settle");$finish;end
        raw=65535;frame;
        if(height!=128)begin $display("FAIL overrange wrap");$finish;end
        rst_n=0;#1;
        if(height!=0 || peak_height!=0)begin $display("FAIL meter reset");$finish;end
`ifndef BASELINE
        x=500;y=65;brightness=0;#1;
        if(rgb!==24'hd7d6d0)begin $display("FAIL brightness empty track");$finish;end
        brightness=64;#1;
        if(rgb!==24'hf0de6b)begin $display("FAIL brightness middle track");$finish;end
        x=678;brightness=127;#1;
        if(rgb!==24'h252c2e)begin $display("FAIL brightness end handle");$finish;end
        x=32;y=368;#1;
        if(rgb===24'h397e75)begin $display("FAIL disabled guide still visible");$finish;end
`endif
        $display("PASS tb_meter_scale: quiet tone, all 32769 amplitudes, raw preservation, full-scale/overrange, release, reset");$finish;
    end
endmodule
