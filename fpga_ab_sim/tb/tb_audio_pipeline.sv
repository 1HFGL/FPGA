`timescale 1ns/1ps
module tb_audio_pipeline;
    reg clk=0,rst_n=0;
    reg [3:0] divider=0;
    wire tick=divider==15;
    reg [47:0] ids={3{16'd1}};
    reg [6:0] volume=127;
    wire [47:0] samples;
    wire signed [15:0] audio;
    reg signed [15:0] previous_sum=0, current_sum;
    reg signed [63:0] total;
    reg signed [22:0] scaled;
    integer cycle, v, frames=0, audible=0;
    synth_engine #(.VOICES(3)) dut(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.voice_active(3'b111),.voice_gate(3'b111),
        .voice_trigger_id_flat(ids),.voice_note_flat({7'd72,7'd60,7'd48}),
        .voice_velocity_flat({3{7'd100}}),.voice_timbre_flat({4'd2,4'd1,4'd0}),
        .voice_pitch_bend_flat(48'd0),.master_volume(volume),.tone_brightness(7'd127),
        .release_done(),.release_trigger_id_flat(),.voice_sample_flat(samples),.audio_sample(audio)
    );
    always #5 clk=~clk;
    always @(posedge clk) if(!rst_n) divider<=0; else divider<=divider+1'b1;
    // Independent arithmetic reference; also check the pre-edge sample seen by
    // a sample_tick consumer such as the serializer.
    always @(posedge clk) begin
        if(!rst_n) previous_sum=0;
        else begin
            scaled=previous_sum*$signed({1'b0,volume});
            if(tick) begin
                if(audio!==scaled[22:7]) $fatal(1,"FAIL: wrong frame at sample_tick");
                frames=frames+1;
                if(audio!=0) audible=audible+1;
            end
            total=0;
            for(v=0;v<3;v=v+1) total=total+$signed(samples[v*16+:16]);
            if(total>32767) current_sum=32767;
            else if(total< -32768) current_sum=-32768;
            else current_sum=total[15:0];
            scaled=current_sum*$signed({1'b0,volume});
            #1;
            if(audio!==scaled[22:7]) $fatal(1,"FAIL: mixer pipeline delay or volume result");
            previous_sum=current_sum;
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        for(cycle=0;cycle<12000;cycle=cycle+1) begin
            @(negedge clk);
            if(cycle%97==0) volume=(cycle%128);
            if(cycle%997==0) ids[15:0]=ids[15:0]+1'b1;
        end
        if(frames<700 || audible<100) $fatal(1,"FAIL: too few exercised audio frames");
        rst_n=0; #2;
        if(audio!==16'd0) $fatal(1,"FAIL: pipeline reset");
        $display("PASS: audio pipeline one-clock delay/reset/retrigger/volume/frame sampling");
        $finish;
    end
endmodule
