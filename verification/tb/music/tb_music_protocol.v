`timescale 1ns/1ps
module tb_music_protocol;
    reg clk=0,rst=0,rx=1,ready=1,cancel_ready=1;
    wire tx,ev,et,can,session,selected,preset;
    reg control_ready=1;
    wire control_valid;wire [6:0] volume,target_volume;wire [10:0] bend,target_bend;
    music_controls controls(.clk(clk),.rst_n(rst),.sample_request(1'b0),.control_valid(control_valid),
        .control_volume(volume),.control_bend(bend),.target_volume(target_volume),.target_bend(target_bend),
        .gain_q16(),.bend_current(),.pitch_ratio_q16());
 reg [15:0] captured[0:63];
    wire [6:0] note,velocity;
    wire bv,be; wire [7:0] bd;
    reg [8191:0] line=0,replies[0:255];
    integer nr=0,read_reply=0,events=0,cancels=0,i;
    reg [6:0] last_note,last_velocity; reg last_type;
    always #10 clk=~clk;
    music_uart_protocol #(.CLKS_PER_BIT(16),.LINE_TIMEOUT_CYCLES(5000),.WATCHDOG_CYCLES(500000)) dut(
        .clk(clk),.rst_n(rst),.rx(rx),.tx(tx),.control_ready(control_ready),.target_volume(target_volume),.target_bend(target_bend),
        .control_valid(control_valid),.control_volume(volume),.control_bend(bend),.event_valid(ev),.event_ready(ready),
        .event_type(et),.event_note(note),.event_velocity(velocity),.cancel_valid(can),.cancel_ready(cancel_ready),
        .voice_count(6'd4),.max_voice_count(6'd4),.steal_count(32'hffffffff),.session_ready(session),.selected_preset(selected),.event_preset(preset));
    uart_rx #(.CLKS_PER_BIT(16)) monitor(.clk(clk),.rst_n(rst),.rx(tx),.valid(bv),.data(bd),.frame_error(be));
    always @(posedge clk) begin
        if(bv) begin
            if(bd==10) begin replies[nr]=line; nr=nr+1; line=0; end
            else line={line,bd};
        end
        if(be) begin $display("FAIL: bad reply frame"); $finish; end
        if(ev && ready) begin captured[events]={preset,et,note,velocity};events=events+1; last_note=note; last_velocity=velocity; last_type=et; end
        if(can && cancel_ready) cancels=cancels+1;
    end
    task send(input [8191:0] text);
        integer a,b;
        begin
            for(a=0;a<text_length(text);a=a+1) begin
                @(negedge clk); rx=0; repeat(16) @(negedge clk);
                for(b=0;b<8;b=b+1) begin rx=(text[(text_length(text)-1-a)*8+:8]>>b)&1; repeat(16) @(negedge clk); end
                rx=1; repeat(16) @(negedge clk);
            end
            repeat(8) @(negedge clk);
        end
    endtask
    task expect_line(input [8191:0] wanted);
        begin
            wait(nr>read_reply);
            if(replies[read_reply]!=wanted) begin $display("FAIL: reply got '%s', expected '%s'",replies[read_reply],wanted); $finish; end
            read_reply=read_reply+1;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=1;
        send("CONTROL 64 1024\n");expect_line("ERROR 0 NOT_READY");
        send("NOTE_ON 60 100 0\n"); expect_line("ERROR 0 NOT_READY");
        if(events!=0 || session) begin $display("FAIL: startup played"); $finish; end
        send("HELLO\n"); expect_line("SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=4 SAMPLE_RATE=48000 FW=music-classic4 TONE=PIANO_ROCK");
        if(!session || cancels!=1) begin $display("FAIL: HELLO did not cancel old session"); $finish; end
        send("NOTE_ON 60 100 0\n"); if(events!=1 || last_note!=60 || !last_type || last_velocity!=100) begin $display("FAIL: note on"); $finish; end
        send("NOTE_ON 60 0 0\n"); if(events!=2 || last_type) begin $display("FAIL: velocity zero"); $finish; end
        send("NOTE_OFF 60 0\n"); if(events!=3 || last_type) begin $display("FAIL: note off"); $finish; end
        send("NOTE_ON 128 100 0\n"); expect_line("ERROR 0 RANGE");
        send("NOTE_OFF 60 1\n"); expect_line("ERROR 0 RANGE");
        send("NOTE_ON 60 100\n"); expect_line("ERROR 0 BAD_CMD");
        send("APPLY 4294967295 255,0 DEAD\n"); expect_line("ERROR 4294967295 UNSUPPORTED");
        send("STATUS?\n"); expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000 PRESET=1 VOLUME=8 BEND=512");
        if(events!=3) begin $display("FAIL: invalid line changed sound"); $finish; end
        ready=0; cancel_ready=0;
        for(i=0;i<16;i=i+1) send("NOTE_ON 60 100 0\n");
        send("NOTE_OFF 60 0\n"); expect_line("ERROR 0 BUSY");
        if(!can || ev) begin $display("FAIL: queue overflow did not flush/cancel"); $finish; end
        cancel_ready=1; repeat(10) @(negedge clk); ready=1;
        repeat(50) @(negedge clk); if(events!=3) begin $display("FAIL: stale queue resurrected"); $finish; end
        send("NOTE_ON 64 99 0\n"); if(events!=4 || last_note!=64) begin $display("FAIL: overflow recovery"); $finish; end
        send("PANIC\n"); if(cancels!=3) begin $display("FAIL: panic"); $finish; end
        repeat(500010) @(negedge clk);
        if(session || cancels!=4) begin $display("FAIL: watchdog failed"); $finish; end
        send("STATUS?\n"); expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000 PRESET=1 VOLUME=8 BEND=512");
        if(session) begin $display("FAIL: STATUS reactivated session"); $finish; end
        send("CONTROL 64 1024\n");expect_line("ERROR 0 NOT_READY");
        send("NOTE_ON 60 100 0\n"); expect_line("ERROR 0 NOT_READY");
        send("HELLO\n"); expect_line("SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=4 SAMPLE_RATE=48000 FW=music-classic4 TONE=PIANO_ROCK");
        send("NOTE_ON 72 100 0\n"); if(events!=5 || !session) begin $display("FAIL: HELLO recovery"); $finish; end
        // Buffered notes retain command-time presets despite later selections.
        ready=0;
        send("NOTE_ON 60 100 0\n");
        send({"PRESET 0",8'd13,8'd10});expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000 PRESET=0 VOLUME=8 BEND=512");
        send("NOTE_ON 64 100 0\n");
        send("PRESET 1\n");expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000 PRESET=1 VOLUME=8 BEND=512");
        send("NOTE_ON 67 100 0\n");
        repeat(8)@(negedge clk);
        if(!ev || {preset,et,note,velocity}!=={1'b1,1'b1,7'd60,7'd100})begin $display("FAIL: head changed under backpressure"); $finish; end
        ready=1;repeat(8)@(negedge clk);
        if(events!=8 || captured[5]!=={1'b1,1'b1,7'd60,7'd100} ||
         captured[6]!=={1'b0,1'b1,7'd64,7'd100} || captured[7]!=={1'b1,1'b1,7'd67,7'd100})begin $display("FAIL: preset ordering"); $finish; end
        send("PRESET 2\n");expect_line("ERROR 0 RANGE");
        send("PRESET -1\n");expect_line("ERROR 0 BAD_CMD");
        send("PRESET\n");expect_line("ERROR 0 BAD_CMD");
        send("PRESET 0 1\n");expect_line("ERROR 0 BAD_CMD");
        send("PRESET 4294967296\n");expect_line("ERROR 0 BAD_CMD");
        send({"PRESET 0",8'd13,"X",8'd10});expect_line("ERROR 0 BAD_CMD");
        if(!selected || events!=8)begin $display("FAIL: invalid preset mutated state"); $finish; end
        // Partial command timeout cannot later turn its suffix into a selection.
        send("PRESET ");repeat(5010)@(negedge clk);send("0\n");expect_line("ERROR 0 UNSUPPORTED");
        send("PRESET 0\n");expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000 PRESET=0 VOLUME=8 BEND=512");
        repeat(500010)@(negedge clk);
        send("PRESET 1\n");expect_line("ERROR 0 NOT_READY");
        if(selected || session)begin $display("FAIL: unready changed preset"); $finish; end
        send("HELLO\n");expect_line("SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=4 SAMPLE_RATE=48000 FW=music-classic4 TONE=PIANO_ROCK");
        if(selected)begin $display("FAIL: reconnect changed physical selection"); $finish; end
        send("CONTROL 64 1024\n");expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000 PRESET=0 VOLUME=64 BEND=1024");
        if(target_volume!=64 || target_bend!=1024)begin $display("FAIL control target");$finish;end
        send("CONTROL 128 512\n");expect_line("ERROR 0 RANGE");
        send("CONTROL 0 1025\n");expect_line("ERROR 0 RANGE");
        send("CONTROL -1 512\n");expect_line("ERROR 0 BAD_CMD");
        send("CONTROL 0 -1\n");expect_line("ERROR 0 BAD_CMD");
        send("CONTROL 1\n");expect_line("ERROR 0 BAD_CMD");
        send("CONTROL 1 2 3\n");expect_line("ERROR 0 BAD_CMD");
        send("CONTROL 4294967296 512\n");expect_line("ERROR 0 BAD_CMD");
        control_ready=0;
        send("CONTROL 0 0\n");expect_line("ERROR 0 BUSY");control_ready=1;
        if(target_volume!=64 || target_bend!=1024)begin $display("FAIL rejected control mutated pair");$finish;end
        send({"CONTROL 0 0",8'd13,8'd10});expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000 PRESET=0 VOLUME=0 BEND=0");
        send("HELLO\n");expect_line("SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=4 SAMPLE_RATE=48000 FW=music-classic4 TONE=PIANO_ROCK");
        if(target_volume!=0 || target_bend!=0)begin $display("FAIL HELLO changed local controls");$finish;end
        rst=0;repeat(5)@(negedge clk);rst=1;repeat(5)@(negedge clk);
        if(target_volume!=8 || target_bend!=512)begin $display("FAIL reset controls");$finish;end
        if(!selected || session || ev)begin $display("FAIL: reset did not restore piano"); $finish; end
        $display("PASS tb_music_protocol: legacy controls, queued preset snapshots, malformed/range/timeout/session/reset, atomic CONTROL and BUSY rejection");$finish;
    end
    initial begin #50000000;begin $display("FAIL: music protocol timeout"); $finish; end end
 function integer text_length;
 input [8191:0] text;
 integer q;
 begin text_length=0;for(q=0;q<1024;q=q+1)if(text[q*8+:8]!=0)text_length=q+1;end
 endfunction
endmodule
