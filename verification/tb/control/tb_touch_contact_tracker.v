`timescale 1ns/1ps
// 新独立测试：同时接真实16声部分配器，检查来源隔离和握手，而非只看事件数。
module tb_touch_contact_tracker;
    reg clk=0,rst=0,connected=1,error=0,fv=0,mode=0;
    reg [1:0] octave=1;
    reg [4:0] active=0;
    reg [39:0] ids=0;
    reg [59:0] xs=0,ys=0;
    reg allow_event=1,allow_cancel=1,manual=0;
    reg [7:0] manual_source=0;
    wire fr,tv,on,guitar,cv,cancel,fault,ar,acr;
    wire [7:0] source,cmask,cvalue;
    wire [6:0] note,velocity;
    wire [1:0] kind,value;
    wire tr=ar && allow_event && !manual;
    wire cr=acr && allow_cancel;
    wire [15:0] gates,held;
    wire [5:0] max_voices;
    wire [127:0] sources;
    wire [111:0] notes;
    integer seen=0,wanted=0,controls=0,cancels=0,k,n;
    reg [16:0] expected[0:127];
    reg stalled=0;reg [16:0] last_payload;
    always #10 clk=~clk;
    touch_contact_tracker dut(.clk(clk),.rst_n(rst),.connected(connected),.stream_error(error),
        .frame_valid(fv),.frame_ready(fr),.contact_active(active),.contact_id(ids),.contact_x(xs),.contact_y(ys),
        .instrument_guitar(mode),.octave(octave),.event_valid(tv),.event_ready(tr),.event_on(on),
        .event_source(source),.event_note(note),.event_velocity(velocity),.event_guitar(guitar),
        .control_valid(cv),.control_ready(1'b1),.control_kind(kind),.control_value(value),
        .cancel_valid(cancel),.cancel_ready(cr),.cancel_mask(cmask),.cancel_value(cvalue),.fault(fault));
    voice_allocator #(.VOICES(16),.IDX_WIDTH(4),.COUNT_WIDTH(6),.SOURCE_WIDTH(8),
        .MERGE_SAME_NOTE(0),.ENABLE_CANCEL(1),.ENABLE_PLAY_CONTROL(1)) allocator(
        .clk(clk),.rst_n(rst),.event_valid(manual || (tv && allow_event)),.event_ready(ar),
        .event_type(manual?1'b1:on),.event_source_id(manual?manual_source:source),
        .event_note(manual?7'd60:note),.event_velocity(velocity),.event_timbre({3'd0,guitar}),
        .expr_valid(1'b0),.expr_ready(),.expr_source_id(8'd0),.expr_note(7'd0),.expr_pitch_bend(16'd0),
        .expr_aftertouch(8'd0),.expr_vibrato_depth(8'd0),.expr_vibrato_rate(8'd0),
        .release_done(16'd0),.cancel_valid(cancel && allow_cancel),.cancel_ready(acr),
        .cancel_mask(cmask),.cancel_value(cvalue),.sustain_on(1'b0),.release_trigger_id_flat(256'd0),
        .voice_active(),.voice_gate(gates),.voice_key_down(held),.voice_source_id_flat(sources),.voice_note_flat(notes),
        .voice_velocity_flat(),.voice_timbre_flat(),.voice_pitch_bend_flat(),.voice_aftertouch_flat(),
        .voice_vibrato_depth_flat(),.voice_vibrato_rate_flat(),.voice_count(),.max_voice_count(max_voices),
        .note_on_count(),.note_off_count(),.steal_count(),.steal_pulse(),.voice_trigger(),.voice_trigger_id_flat());
    always @(posedge clk)if(rst)begin
        if(stalled && (!tv || {on,source,note,guitar}!==last_payload))begin $display("FAIL stalled touch payload");$finish;end
        stalled=tv && !tr;last_payload={on,source,note,guitar};
        if(tv && tr)begin
            if(seen>=wanted || {on,source,note,guitar}!==expected[seen] || velocity!=96)begin
                $display("FAIL touch event %0d got=%h expected=%h wanted=%0d",seen,{on,source,note,guitar},expected[seen],wanted);$finish;end
            seen=seen+1;
        end
        if(cv)begin
            controls=controls+1;
            if(kind!=1 || value!=1)begin $display("FAIL touch control");$finish;end
        end
        if(cancel && cr)begin
            cancels=cancels+1;
            if(cmask!=8'hf0 || cvalue!=8'h40)begin $display("FAIL touch cancel scope");$finish;end
        end
    end
    task expect_event;
        input eon;input [7:0] src;input [6:0] enote;input eguitar;
        begin expected[wanted]={eon,src,enote,eguitar};wanted=wanted+1;end
    endtask
    task point;
        input integer slot,id,px,py;
        begin active[slot]=1;ids[slot*8+:8]=id;xs[slot*12+:12]=px;ys[slot*12+:12]=py;end
    endtask
    task frame;
        begin
            @(negedge clk);while(!fr)@(negedge clk);fv=1;
            @(negedge clk);fv=0;
            while(!fr)@(negedge clk);
            repeat(25)@(negedge clk);
            if(seen!=wanted)begin $display("FAIL missing touch event %0d/%0d",seen,wanted);$finish;end
        end
    endtask
    task inject_other;
        input [7:0] src;
        begin @(negedge clk);manual_source=src;manual=1;
            @(negedge clk);while(!ar)@(negedge clk);manual=0;
            repeat(25)@(negedge clk);
        end
    endtask
    initial begin
        #3;rst=1;repeat(5)@(negedge clk);
        point(0,10,80,520);point(1,20,320,520);point(2,30,542,520);
        expect_event(1,8'h40,60,0);expect_event(1,8'h41,64,0);expect_event(1,8'h42,67,0);frame;
        // 重排不改变任何来源；换区也不让按住的三和弦跳八度。
        point(0,30,542,520);point(1,10,80,520);point(2,20,320,520);frame;
        octave=2;frame;
        point(1,10,210,520);expect_event(0,8'h40,60,0);expect_event(1,8'h40,74,0);frame;
        mode=1;frame; // 切模式后旧触点冻结至抬手。
        active[0]=0;expect_event(0,8'h42,67,0);frame;
        point(0,40,940,550);expect_event(1,8'h42,84,1);frame;
        active=0;expect_event(0,8'h40,74,0);expect_event(0,8'h41,64,0);expect_event(0,8'h42,84,1);frame;
        mode=0;octave=1;
        point(0,1,80,520);point(1,2,80,520);
        expect_event(1,8'h40,60,0);expect_event(1,8'h41,60,0);frame;
        active[0]=0;expect_event(0,8'h40,60,0);frame;
        active=0;expect_event(0,8'h41,60,0);frame;
        point(0,3,900,40);frame;frame;
        point(0,3,80,520);frame;
        if(controls!=1)begin $display("FAIL repeated/control-to-key trigger");$finish;end
        active=0;frame;
        point(0,4,80,520);expect_event(1,8'h40,60,0);frame;
        point(0,4,900,40);expect_event(0,8'h40,60,0);frame;
        if(controls!=1)begin $display("FAIL key slide toggled control");$finish;end
        active=0;frame;
        // 五触点同时发声和释放，覆盖完整快照上界及不同内部槽。
        point(0,100,80,520);point(1,101,210,520);point(2,102,320,520);
        point(3,103,542,520);point(4,104,940,520);
        expect_event(1,8'h40,60,0);expect_event(1,8'h41,62,0);expect_event(1,8'h42,64,0);
        expect_event(1,8'h43,67,0);expect_event(1,8'h44,72,0);frame;
        active=0;
        expect_event(0,8'h40,60,0);expect_event(0,8'h41,62,0);expect_event(0,8'h42,64,0);
        expect_event(0,8'h43,67,0);expect_event(0,8'h44,72,0);frame;
        // 同音实体/PC来源留在真实分配器内，触摸断连不能关它们。
        inject_other(8'h01);inject_other(8'h80);
        point(0,5,80,520);expect_event(1,8'h40,60,0);frame;
        allow_cancel=0;@(negedge clk);connected=0;
        repeat(15)@(negedge clk);
        if(!cancel || fr)begin $display("FAIL disconnect cancel handshake");$finish;end
        allow_cancel=1;repeat(30)@(negedge clk);
        n=0;
        for(k=0;k<16;k=k+1)begin
            if(gates[k] && (sources[k*8+:8]&8'hf0)==8'h40)begin $display("FAIL touch stuck after cancel");$finish;end
            if(gates[k] && (sources[k*8+:8]==8'h01 || sources[k*8+:8]==8'h80))n=n+1;
        end
        if(n!=2)begin $display("FAIL disconnect killed other sources");$finish;end
        connected=1;active=0;frame;
        // 重复ID视为坏快照，清理会话；不凭两个相同ID生成两个音。
        point(0,9,80,520);point(1,9,210,520);frame;
        if(!fault || cancels!=2)begin $display("FAIL duplicate ID did not cancel");$finish;end
        active=0;frame;
        // 已提出事件受背压时必须保持；解除背压后再处理断连。
        point(0,11,80,520);expect_event(1,8'h40,60,0);allow_event=0;
        @(negedge clk);fv=1;@(negedge clk);fv=0;
        wait(tv);repeat(30)@(negedge clk);connected=0;
        repeat(20)@(negedge clk);allow_event=1;
        repeat(80)@(negedge clk);
        if(seen!=wanted || cancels!=3)begin $display("FAIL pending event/cancel ordering");$finish;end
        if(max_voices!=16)begin $display("FAIL did not fill 16 voice pool: %0d",max_voices);$finish;end
        connected=1;active=0;frame;
        point(0,77,80,520);allow_event=0;
        @(negedge clk);fv=1;@(negedge clk);fv=0;
        wait(tv);repeat(3)@(negedge clk); // 有未接受事件时复位，复位双方共同清理。
        #3;rst=0;#1;if(tv || cv || cancel || fault)begin $display("FAIL touch reset");$finish;end
        $display("PASS tb_touch_contact_tracker: %0d exact events, five contacts/IDs/reorder/same-note/glissando/octave/mode, controls, full16 allocator isolation, disconnect/duplicate/backpressure/pending reset",seen);$finish;
    end
    initial begin #3000000;$display("FAIL touch tracker timeout state=%0d seen=%0d/%0d",dut.state,seen,wanted);$finish;end
endmodule
