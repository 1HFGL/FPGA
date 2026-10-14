`timescale 1ns/1ps
module tb_retrigger_audio;
    localparam N=16;
    reg clk=0,rst_n=0,ev=0,on=0;
    reg [4:0] source=0;
    reg [6:0] note=60;
    reg [5:0] divider=0;
    wire tick=divider==63;
    wire ready;
    wire [N-1:0] active,gate,down,done;
    wire [N*16-1:0] ids,done_ids,samples,bends;
    wire [N*7-1:0] notes,velocities;
    wire [N*4-1:0] timbres;
    wire [5:0] count;
    wire signed [15:0] audio;
    reg [N-1:0] heard=0;
    integer k,timeout;
    reg [15:0] old_id;
    always #5 clk=~clk;
    always @(posedge clk) if(!rst_n) divider<=0; else divider<=divider+1'b1;
    voice_allocator #(.VOICES(N),.CHECK_RELEASE_ID(1)) allocation(
        .clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready),.event_type(on),
        .event_source_id(source),.event_note(note),.event_velocity(7'd100),.event_timbre(4'd0),
        .sustain_on(1'b0),.source_clear_valid(1'b0),.source_clear_ready(),.source_clear_id(5'd0),.source_clear_mask(5'd0),
        .expr_valid(1'b0),.expr_ready(),.expr_source_id(5'd0),.expr_note(7'd0),.expr_pitch_bend(16'd0),
        .expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(done),.release_trigger_id_flat(done_ids),.voice_active(active),.voice_gate(gate),
        .voice_key_down(down),.voice_trigger_id_flat(ids),.voice_source_id_flat(),.voice_note_flat(notes),
        .voice_velocity_flat(velocities),.voice_timbre_flat(timbres),.voice_pitch_bend_flat(bends),
        .voice_aftertouch_flat(),.voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),.voice_count(count),
        .max_voice_count(),.note_on_count(),.note_off_count(),.steal_count(),.steal_pulse()
    );
    synth_engine #(.VOICES(N)) synthesis(
        .clk(clk),.rst_n(rst_n),.sample_tick(tick),.voice_active(active),.voice_gate(gate),
        .voice_trigger_id_flat(ids),.voice_note_flat(notes),.voice_velocity_flat(velocities),
        .voice_timbre_flat(timbres),.voice_pitch_bend_flat(bends),.master_volume(7'd127),.tone_brightness(7'd127),
        .release_done(done),.release_trigger_id_flat(done_ids),.voice_sample_flat(samples),.audio_sample(audio)
    );
    task send(input bit start,input [4:0] origin,input [6:0] pitch);
        begin
            wait(ready); @(negedge clk); ev=1; on=start; source=origin; note=pitch;
            @(negedge clk); ev=0; wait(ready); @(negedge clk);
        end
    endtask
    always @(negedge clk) if(rst_n) begin
        for(integer v=0;v<N;v=v+1) if(samples[v*16+:16]!==16'd0 && active[v]) heard[v]=1;
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        for(k=0;k<N;k=k+1) send(1,k,48+k);
        repeat(5000) @(negedge clk);
        if(count!=N || heard!={N{1'b1}} || synthesis.g_voice[0].env_level<10000)
            $fatal(1,"Sixteen independent voices did not generate nonzero samples");
        old_id=ids[15:0]; send(1,0,48);
        if(!gate[0] || ids[15:0]!=old_id+16'd1 || count!=N) $fatal(1,"Held retrigger changed allocation incorrectly");
        wait(synthesis.g_voice[0].trigger_seen==ids[15:0]); @(negedge clk);
        if(synthesis.g_voice[0].env_level!=0) $fatal(1,"New trigger did not restart envelope while gate stayed high");
        repeat(3000) @(negedge clk);
        if(synthesis.g_voice[0].env_level<10000) $fatal(1,"Retrigger did not enter attack again");
        for(k=0;k<N;k=k+1) send(0,k,48+k);
        timeout=0;
        while(count!=0 && timeout<25000) begin @(negedge clk); timeout=timeout+1; end
        if(count!=0) $fatal(1,"Release generation feedback failed to reclaim all tails");
        $display("PASS: tb_retrigger_audio 16 voices/held-gate retrigger/envelope/true completion"); $finish;
    end
    initial begin #2000000; $fatal(1,"Audio-control watchdog"); end
endmodule
