`timescale 1ns/1ps
module tb_display_reset_gain;
    reg sc=0,pc=0,run_pixel=1,rst_n=0,valid=0;
    reg signed [15:0] sample=0;
    wire [23:0] rgb;
    wire de,hs,vs,fs,drop;
    integer received=0,dropped=0,i;
    reg [7:0] expected;
    always #10 sc=~sc;
    always #15 if(run_pixel) pc=~pc;
    instrument_display dut(.sys_clk(sc),.pixel_clk(pc),.rst_n(rst_n),
        .key_down(13'd0),.volume(7'd0),.pitch_bend(16'sd0),.octave(2'd1),
        .sustain(1'b0),.instrument_guitar(1'b0),.audio_valid(valid),.audio_sample(sample),
        .lcd_rgb(rgb),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.frame_start(fs),.display_sample_drop(drop));
    always @(posedge sc) if(drop) dropped=dropped+1;
    always @(posedge pc) begin
        #1;
        if(rst_n && dut.sample_pixel_valid) begin
            if(dut.sample8!==expected) begin
                $display("FAIL gain expected=%h actual=%h",expected,dut.sample8);$finish;
            end
            received=received+1;
        end
    end
    task send;
        input signed [15:0] value;
        input [7:0] want;
        begin
            expected=want;
            @(negedge sc);sample=value;valid=1;
            @(negedge sc);valid=0;
            repeat(20) @(negedge sc);
        end
    endtask
    initial begin
        #103;rst_n=1;repeat(20) @(negedge sc);
        send(16'sd0,8'h00);
        send(16'sd4095,8'h7f);
        send(16'sd4096,8'h7f);
        send(16'sd32767,8'h7f);
        send(-16'sd4096,8'h80);
        send(-16'sd4097,8'h80);
        send(-16'sd32768,8'h80);
        send(-16'sd1,8'hff); // 负数按补码高位量化，不错误零扩展
        if(received!=8) begin $display("FAIL gain sample count");$finish;end
        @(negedge pc);run_pixel=0;
        @(negedge sc);valid=1;sample=0;expected=0;
        repeat(20) @(negedge sc);
        valid=0;
        if(dropped==0) begin $display("FAIL stopped pixel clock drop flag");$finish;end
        // 同时清两域，像素时钟停着也必须异步清DE和有效快照。
        rst_n=0;#1;
        if(de!==0 || rgb!==0 || dut.u_wave.wave_ready!==0) begin $display("FAIL top async reset");$finish;end
        #60;run_pixel=1;#120;rst_n=1;
        repeat(20) @(negedge sc);
        if(received!=8) begin $display("FAIL stale sample after reset");$finish;end
        send(16'sd32,8'h01);
        if(received!=9) begin $display("FAIL restart sample");$finish;end
        $display("PASS tb_display_reset_gain: saturation, sign, stopped clock, common reset and restart");$finish;
    end
    initial begin #1000000;$display("FAIL reset/gain timeout");$finish;end
endmodule
