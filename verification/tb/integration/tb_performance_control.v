`timescale 1ns/1ps
// C最新控制行为在主工程的适配验证，队友测试文件不参与修改。
module tb_performance_control;
    reg clk=0,rst_n=0,ev=0,et=0,sustain=0,cancel=0;
    reg [7:0] source=0;
    reg [6:0] note=60;
    reg [15:0] completed_mask=0;
    reg [255:0] completed_ids=0;
    wire ready,cancel_ready;
    wire [15:0] active,gate,down;
    wire [255:0] ids;
    wire [127:0] sources;
    wire [111:0] notes;
    wire [5:0] count;
    reg [12:0] press=0,release_key=0;
    reg [1:0] octave=1;
    reg er=0;
    wire qv,qt,overflow;
    wire [6:0] qn;
    integer i,slot,ons=0,offs=0;
    voice_allocator #(.VOICES(16),.IDX_WIDTH(4),.COUNT_WIDTH(6),.SOURCE_WIDTH(8),
        .MERGE_SAME_NOTE(0),.ENABLE_CANCEL(1),.ENABLE_PLAY_CONTROL(1),.CHECK_RELEASE_ID(1)) dut(
        .clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready),.event_type(et),
        .event_source_id(source),.event_note(note),.event_velocity(7'd100),.event_timbre(4'd0),
        .expr_valid(1'b0),.expr_ready(),.expr_source_id(8'd0),.expr_note(7'd0),.expr_pitch_bend(16'd0),
        .expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(completed_mask),.cancel_valid(cancel),.cancel_ready(cancel_ready),.cancel_mask(8'h80),.cancel_value(8'h80),
        .voice_active(active),.voice_gate(gate),.voice_source_id_flat(sources),.voice_note_flat(notes),
        .voice_velocity_flat(),.voice_timbre_flat(),.voice_pitch_bend_flat(),.voice_aftertouch_flat(),
        .voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),.voice_count(count),.max_voice_count(),
        .note_on_count(),.note_off_count(),.steal_count(),.steal_pulse(),.voice_trigger(),
        .sustain_on(sustain),.release_trigger_id_flat(completed_ids),.voice_trigger_id_flat(ids),.voice_key_down(down));
    event_encoder #(.KEY_COUNT(13),.SOURCE_WIDTH(8),.MAX_EVENTS(2),.PTR_WIDTH(1),
        .CHROMATIC_KEYS(1),.ENABLE_PLAY_CONTROL(1)) enc(
        .clk(clk),.rst_n(rst_n),.key_press(press),.key_release(release_key),
        .key_velocity_flat({13{7'd100}}),.input_timbre(4'd0),.octave_select(octave),.input_overflow(overflow),
        .event_valid(qv),.event_type(qt),.event_source_id(),.event_note(qn),.event_velocity(),.event_timbre(),.event_ready(er));
    always #10 clk=~clk;
    task event_send;
        input on;
        input [7:0] src;
        input [6:0] pitch;
        begin
            @(negedge clk);wait(ready);ev=1;et=on;source=src;note=pitch;
            @(negedge clk);ev=0;wait(ready);@(negedge clk);
        end
    endtask
    task pulse_key;
        input on;
        begin @(negedge clk);press=on;release_key=!on;@(negedge clk);press=0;release_key=0;end
    endtask
    initial begin
        repeat(6)@(negedge clk);rst_n=1;
        event_send(1,0,60);event_send(1,128,60);
        if(count!=2)begin $display("FAIL: source separation");$finish;end
        event_send(1,0,60);
        if(ids[15:0]!=2 || count!=2)begin $display("FAIL: held-gate retrigger generation");$finish;end
        sustain=1;event_send(0,0,60);
        if(down[0] || !gate[0])begin $display("FAIL: keydown/sustain separation");$finish;end
        @(negedge clk);cancel=1;wait(cancel_ready);@(negedge clk);cancel=0;
        if(gate[1] || !gate[0])begin $display("FAIL: cleanup sustain isolation");$finish;end
        sustain=0;repeat(3)@(negedge clk);completed_mask=16'hffff;
        completed_ids[15:0]=1;completed_ids[31:16]=1;
        repeat(5)@(negedge clk);
        if(!active[0] || active[1])begin $display("FAIL: stale completion generation");$finish;end
        completed_ids[15:0]=2;repeat(5)@(negedge clk);
        if(count!=0)begin $display("FAIL: actual completion generation");$finish;end
        // 按下锁音区，背压期间切档，松键仍回送原音符。
        pulse_key(1);repeat(4)@(negedge clk);octave=2;pulse_key(0);repeat(4)@(negedge clk);
        if(!qv || !qt || qn!=60)begin $display("FAIL: queued press snapshot");$finish;end
        er=1;@(negedge clk);er=0;
        if(!qv || qt || qn!=60)begin $display("FAIL: queued release octave lock");$finish;end
        er=1;repeat(4)@(negedge clk);er=0;
        // 堵塞两项FIFO并填满每键四项暂存，必须锁存溢出，停止发送。
        for(i=0;i<8;i=i+1)begin pulse_key(1);pulse_key(0);end
        repeat(8)@(negedge clk);
        if(!overflow || qv)begin $display("FAIL: overflow containment");$finish;end
        rst_n=0;repeat(4)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
        if(overflow || count!=0)begin $display("FAIL: fault reset");$finish;end
        $display("PASS tb_performance_control: held retrigger/generation/sustain/source cleanup/octave snapshot/backpressure/overflow/reset");$finish;
    end
    initial begin #1000000;$display("FAIL: control timeout");$finish;end
endmodule
