`timescale 1ns/1ps
// 直接注入事件验证 C -> 四声部包络；同音重触发不能靠 gate 边沿代替。
module tb_allocator_trigger;
    reg clk=0, rst_n=0, event_valid=0, event_type=0;
    reg [4:0] source=0;
    reg [6:0] note=0;
    wire ready, sounding, valid;
    wire [3:0] gates, active, trigger, done;
    wire [27:0] notes, velocities;
    wire [5:0] count;
    wire signed [15:0] sample;
    integer clock_count=0, trigger_count=0;
    reg [3:0] last_trigger=0;
    wire request=(clock_count%8==0);
    always #10 clk=~clk;
    always @(negedge clk) if(!rst_n) clock_count=0; else clock_count=clock_count+1;
    always @(posedge clk) begin
        #1;
        if(|trigger) begin
            if((trigger & (trigger-1'b1))!=0 || (trigger & gates)!=trigger)
                $fatal(1,"invalid allocator trigger");
            trigger_count=trigger_count+1; last_trigger=trigger;
        end
    end
    voice_allocator #(.VOICES(4)) alloc (
        .clk(clk), .rst_n(rst_n), .event_valid(event_valid), .event_ready(ready),
        .event_type(event_type), .event_source_id(source), .event_note(note),
        .event_velocity(7'd100), .event_timbre(4'd0), .release_done(done),
        .cancel_valid(1'b0), .cancel_ready(), .cancel_mask(5'd0), .cancel_value(5'd0),
        .expr_valid(1'b0), .expr_ready(), .expr_source_id(5'd0), .expr_note(7'd0),
        .expr_pitch_bend(16'd0), .expr_aftertouch(8'd0),
        .expr_vibrato_depth(8'd0), .expr_vibrato_rate(8'd0),
        .voice_gate(gates), .voice_active(active), .voice_trigger(trigger),
        .voice_note_flat(notes), .voice_velocity_flat(velocities), .voice_count(count),
        .voice_source_id_flat(), .voice_timbre_flat(), .voice_pitch_bend_flat(),
        .voice_aftertouch_flat(), .voice_vibrato_depth_flat(), .voice_vibrato_rate_flat(),
        .max_voice_count(), .note_on_count(), .note_off_count(), .steal_count(), .steal_pulse()
    );
    voice_bank_adsr #(.ATTACK_SAMPLES(4), .DECAY_SAMPLES(8), .RELEASE_SAMPLES(20),
        .MIX_SHIFT(5)) bank (
        .clk(clk), .rst_n(rst_n), .sample_request(request), .voice_gate(gates),
        .voice_retrigger(trigger), .voice_note_flat(notes), .voice_velocity_flat(velocities),
        .release_done(done), .sounding(sounding), .sample_data(sample),
        .sample_valid(valid), .env_level_flat(), .voice_active(), .sample_clipped()
    );
    task send_event(input bit on, input [4:0] src, input [6:0] n);
        begin
            @(negedge clk); wait(ready); event_valid=1; event_type=on; source=src; note=n;
            @(negedge clk); event_valid=0;
            repeat(12) @(negedge clk);
            if(!ready) $fatal(1,"allocator did not complete event");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        send_event(1,0,60); send_event(1,1,64); send_event(1,2,67); send_event(1,3,72);
        repeat(160) @(negedge clk);
        if(count!=4 || gates!=15 || trigger_count!=4) $fatal(1,"four voice triggers failed");
        send_event(1,4,76); // 满载：抢占最老的声部0；gate始终为1。
        if(last_trigger!=1 || notes[6:0]!=76 || trigger_count!=5) $fatal(1,"steal trigger missing");
        send_event(0,0,60);
        if(gates!=15 || count!=4 || trigger_count!=5) $fatal(1,"stolen key off killed new note");
        send_event(1,4,76); // 完全相同的源与音符仍必须重触发一次。
        if(last_trigger!=1 || trigger_count!=6) $fatal(1,"same-note retrigger missing");
        send_event(0,1,64);
        if(gates[1]!=0 || active[1]!=1 || done[1]!=0) $fatal(1,"tail retired early");
        repeat(180) @(negedge clk);
        if(active[1]!=0 || done[1]!=1 || count!=3) $fatal(1,"release feedback failed");
        send_event(1,5,65);
        if(last_trigger!=2 || trigger_count!=7 || count!=4) $fatal(1,"free voice not reused");
        rst_n=0; repeat(4) @(negedge clk);
        if(trigger!=0 || gates!=0 || count!=0 || sample!=0) $fatal(1,"allocator/bank reset failed");
        $display("PASS tb_allocator_trigger: four notes, steal, same-note retrigger, release feedback, reset");
        $finish;
    end
    initial begin #1000000; $fatal(1,"allocator trigger timeout"); end
endmodule
