`timescale 1ns/1ps
module tb_voice_control #(parameter integer N=4);
    reg clk=0, rst_n=0, ev=0, et=0, sustain=0, clear_valid=0, expr=0;
    reg [4:0] src=0, clear_id=0, clear_mask=0, expr_src=0;
    reg [6:0] note=0, expr_note=0;
    reg [15:0] bend=0;
    reg [N-1:0] done=0;
    reg [N*16-1:0] done_id=0;
    wire ready, clear_ready, expr_ready;
    wire [N-1:0] active, gate, down;
    wire [N*16-1:0] ids, bends;
    wire [N*5-1:0] sources;
    wire [N*7-1:0] notes;
    wire [5:0] count;
    integer a,b,c,k;
    reg [15:0] prior_id;
    always #5 clk=~clk;
    voice_allocator #(.VOICES(N),.TIME_WIDTH(8),.CHECK_RELEASE_ID(1)) dut(
        .clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready),.event_type(et),
        .event_source_id(src),.event_note(note),.event_velocity(7'd100),.event_timbre(4'd0),
        .sustain_on(sustain),.source_clear_valid(clear_valid),.source_clear_ready(clear_ready),
        .source_clear_id(clear_id),.source_clear_mask(clear_mask),
        .expr_valid(expr),.expr_ready(expr_ready),.expr_source_id(expr_src),.expr_note(expr_note),
        .expr_pitch_bend(bend),.expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(done),.release_trigger_id_flat(done_id),.voice_active(active),.voice_gate(gate),
        .voice_key_down(down),.voice_trigger_id_flat(ids),.voice_source_id_flat(sources),.voice_note_flat(notes),
        .voice_velocity_flat(),.voice_timbre_flat(),.voice_pitch_bend_flat(bends),.voice_aftertouch_flat(),
        .voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),.voice_count(count),.max_voice_count(),
        .note_on_count(),.note_off_count(),.steal_count(),.steal_pulse()
    );
    task reset;
        begin
            @(negedge clk); rst_n=0; ev=0; expr=0; clear_valid=0; sustain=0; done=0; done_id=0;
            repeat(3) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
        end
    endtask
    task send(input bit on, input [4:0] origin, input [6:0] pitch);
        begin
            wait(ready); @(negedge clk); ev=1; et=on; src=origin; note=pitch;
            @(negedge clk); ev=0; wait(ready); @(negedge clk);
        end
    endtask
    function integer held(input [4:0] origin, input [6:0] pitch);
        integer v;
        begin
            held=-1;
            for(v=0;v<N;v=v+1)
                if(active[v] && down[v] && sources[v*5+:5]==origin && notes[v*7+:7]==pitch) held=v;
        end
    endfunction
    initial begin
        reset(); send(1,0,60); a=held(0,60); prior_id=ids[a*16+:16];
        send(1,0,60);
        if(count!=1 || !gate[a] || ids[a*16+:16] != prior_id+16'd1) $fatal(1,"Held-note retrigger missing");
        send(1,16,60); b=held(16,60);
        if(count!=2 || b==a || b<0) $fatal(1,"Equal notes from different origins merged");
        send(0,17,60);
        if(!down[a] || !down[b]) $fatal(1,"Unmatched source note-off closed a voice");
        @(negedge clk); expr=1; expr_src=17; expr_note=60; bend=123;
        @(negedge clk); expr=0; wait(expr_ready); @(negedge clk);
        if(bends!=0) $fatal(1,"Expression leaked through note-only fallback");
        send(0,0,60);
        if(!active[a] || gate[a] || !gate[b]) $fatal(1,"Release/source isolation failed");
        send(1,0,60); c=held(0,60);
        if(count!=3 || c==a || !active[a]) $fatal(1,"Old tail was not preserved with free capacity");
        send(0,0,60);
        @(negedge clk); done[c]=1; done_id[c*16+:16]=ids[c*16+:16]-16'd1;
        repeat(4) @(negedge clk);
        if(!active[c]) $fatal(1,"Stale release completion reclaimed new trigger");
        done_id[c*16+:16]=ids[c*16+:16]; repeat(3) @(negedge clk);
        if(active[c]) $fatal(1,"Current release completion not accepted");
        done=0; sustain=1; send(1,0,62); c=held(0,62); send(0,0,62);
        if(down[c] || !gate[c] || !active[c]) $fatal(1,"Pedal did not retain released voice");
        sustain=0; repeat(3) @(negedge clk);
        if(gate[c] || !gate[b] || !down[b]) $fatal(1,"Pedal-up released a held key");
        reset(); sustain=1; send(1,0,60); send(1,16,60); a=held(0,60); b=held(16,60);
        wait(clear_ready); @(negedge clk); clear_valid=1; clear_id=16; clear_mask=16;
        @(negedge clk); clear_valid=0; wait(ready); @(negedge clk);
        if(!down[a] || !gate[a] || down[b] || gate[b]) $fatal(1,"Source-group cleanup affected local input or respected pedal");
        reset(); repeat(220) @(negedge clk);
        send(1,0,48); repeat(40) @(negedge clk);
        for(k=1;k<N;k=k+1) send(1,k,48+k);
        repeat(600) @(negedge clk); // multiple old TIME_WIDTH=8 clock wraps
        send(1,30,90);
        if(held(0,48)!=-1 || held(30,90)<0 || held(1,49)<0) $fatal(1,"Uptime changed oldest-voice order");
        send(1,1,49); send(1,29,91);
        if(held(1,49)<0 || held(2,50)!=-1) $fatal(1,"Retrigger did not refresh age ordering");
        reset(); for(k=0;k<N;k=k+1) send(1,k,48+k);
        sustain=1; send(0,N-1,48+N-1); send(1,30,90);
        if(held(0,48)<0 || held(30,90)<0 || active!= {N{1'b1}}) $fatal(1,"Released voice not preferred over held oldest");
        $display("PASS: tb_voice_control N=%0d retrigger/source/tail/pedal/cleanup/release_id/uptime",N);
        $finish;
    end
    initial begin #2000000; $fatal(1,"Voice-control watchdog"); end
endmodule
module tb_voice_control_16;
    tb_voice_control #(.N(16)) test();
endmodule
