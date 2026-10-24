`timescale 1ns/1ps
module tb_architecture_ui;
    reg [11:0] x=0,y=0;
    reg [3:0] shift=0;
    reg guitar=0;
    wire e0,e1,t0,t1;
    wire [5:0] g0,g1,tc0,tc1,tr0,tr1;
    wire [4:0] c0,c1,r0,r1;
    wire [2:0] tg0,tg1;
    wire [23:0] color0,color1,base0,base1;
    instrument_panel_ui dut(.x(x),.y(y),.key_down(13'h1001),.volume(7'd127),.pitch_bend(-16'sd32767),
        .octave(2'd2),.sustain(1'b0),.instrument_guitar(guitar),.wave_ready(1'b1),
        .wave_min(-16'sd230),.wave_max(16'sd410),.peak_level(16'd410),.gain_shift(shift),
        .activity(39'd0),.meter_level(16'd410),.meter_peak(16'd500),
        .text_enable(e0),.text_glyph(g0),.text_column(c0),.text_row(r0),.text_color(color0),
        .title_enable(t0),.title_glyph(tg0),.title_column(tc0),.title_row(tr0),.base_rgb(base0));
    instrument_panel_ui_original reference(.x(x),.y(y),.key_down(13'h1001),.volume(7'd127),.pitch_bend(-16'sd32767),
        .octave(2'd2),.sustain(1'b0),.instrument_guitar(guitar),.wave_ready(1'b1),
        .wave_min(-16'sd230),.wave_max(16'sd410),.peak_level(16'd410),.gain_shift(shift),
        .activity(39'd0),.meter_level(16'd410),.meter_peak(16'd500),
        .text_enable(e1),.text_glyph(g1),.text_column(c1),.text_row(r1),.text_color(color1),
        .title_enable(t1),.title_glyph(tg1),.title_column(tc1),.title_row(tr1),.base_rgb(base1));
    integer p,s,xx,yy,checks=0;
    initial begin
        for(p=0;p<2;p=p+1)begin
            guitar=p;
            for(s=0;s<16;s=s+1)begin
                shift=s;
                for(yy=168;yy<200;yy=yy+1)begin
                    for(xx=704;xx<840;xx=xx+1)begin
                        x=xx;y=yy;#1;
                        if({e0,g0,c0,r0,color0,t0,tg0,tc0,tr0,base0}!==
                           {e1,g1,c1,r1,color1,t1,tg1,tc1,tr1,base1})begin
                            $display("FAIL architecture UI mode=%0d shift=%0d x=%0d y=%0d",p,s,xx,yy);$finish;
                        end
                        checks=checks+1;
                    end
                end
            end
        end
        $display("PASS tb_architecture_ui: %0d exact pixel requests, both modes, nine gains and invalid7",checks);$finish;
    end
endmodule
