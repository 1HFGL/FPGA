`timescale 1ns/1ps
module tb_uart_protocol;
    reg clk=0,rst=0,rx=1,ready=1,cancel_ready=1;
    wire tx,ev,et,can,session;
    wire [6:0] note,velocity;
    wire bv,be; wire [7:0] bd;
    string line="",replies[0:255];
    integer nr=0,read_reply=0,events=0,cancels=0,i;
    reg [6:0] last_note,last_velocity; reg last_type;
    always #10 clk=~clk;
    uart_synth_protocol #(.CLKS_PER_BIT(16),.LINE_TIMEOUT_CYCLES(5000),.WATCHDOG_CYCLES(500000)) dut(
        .clk(clk),.rst_n(rst),.rx(rx),.tx(tx),.event_valid(ev),.event_ready(ready),
        .event_type(et),.event_note(note),.event_velocity(velocity),.cancel_valid(can),.cancel_ready(cancel_ready),
        .voice_count(6'd4),.max_voice_count(6'd4),.steal_count(32'hffffffff),.session_ready(session));
    uart_rx #(.CLKS_PER_BIT(16)) monitor(.clk(clk),.rst_n(rst),.rx(tx),.valid(bv),.data(bd),.frame_error(be));
    always @(posedge clk) begin
        if(bv) begin
            if(bd==10) begin replies[nr]=line; nr=nr+1; line=""; end
            else line={line,bd};
        end
        if(be) $fatal(1,"bad reply frame");
        if(ev && ready) begin events=events+1; last_note=note; last_velocity=velocity; last_type=et; end
        if(can && cancel_ready) cancels=cancels+1;
    end
    task send(input string text);
        integer a,b;
        begin
            for(a=0;a<text.len();a=a+1) begin
                @(negedge clk); rx=0; repeat(16) @(negedge clk);
                for(b=0;b<8;b=b+1) begin rx=(text[a]>>b)&1; repeat(16) @(negedge clk); end
                rx=1; repeat(16) @(negedge clk);
            end
            repeat(8) @(negedge clk);
        end
    endtask
    task expect_line(input string wanted);
        begin
            wait(nr>read_reply);
            if(replies[read_reply]!=wanted) $fatal(1,"reply got '%s', expected '%s'",replies[read_reply],wanted);
            read_reply=read_reply+1;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=1;
        send("NOTE_ON 60 100 0\n"); expect_line("ERROR 0 NOT_READY");
        if(events!=0 || session) $fatal(1,"startup played");
        send("HELLO\n"); expect_line("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE");
        if(!session || cancels!=1) $fatal(1,"HELLO did not cancel old session");
        send("NOTE_ON 60 100 0\n"); if(events!=1 || last_note!=60 || !last_type || last_velocity!=100) $fatal(1,"note on");
        send("NOTE_ON 60 0 0\n"); if(events!=2 || last_type) $fatal(1,"velocity zero");
        send("NOTE_OFF 60 0\n"); if(events!=3 || last_type) $fatal(1,"note off");
        send("NOTE_ON 128 100 0\n"); expect_line("ERROR 0 RANGE");
        send("NOTE_OFF 60 1\n"); expect_line("ERROR 0 RANGE");
        send("NOTE_ON 60 100\n"); expect_line("ERROR 0 BAD_CMD");
        send("APPLY 4294967295 255,0 DEAD\n"); expect_line("ERROR 4294967295 UNSUPPORTED");
        send("STATUS?\n"); expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000");
        if(events!=3) $fatal(1,"invalid line changed sound");
        ready=0; cancel_ready=0;
        for(i=0;i<16;i=i+1) send("NOTE_ON 60 100 0\n");
        send("NOTE_OFF 60 0\n"); expect_line("ERROR 0 BUSY");
        if(!can || ev) $fatal(1,"queue overflow did not flush/cancel");
        cancel_ready=1; repeat(10) @(negedge clk); ready=1;
        repeat(50) @(negedge clk); if(events!=3) $fatal(1,"stale queue resurrected");
        send("NOTE_ON 64 99 0\n"); if(events!=4 || last_note!=64) $fatal(1,"overflow recovery");
        send("PANIC\n"); if(cancels!=3) $fatal(1,"panic");
        repeat(500010) @(negedge clk);
        if(session || cancels!=4) $fatal(1,"watchdog failed");
        send("STATUS?\n"); expect_line("STATUS VOICE_COUNT=4 MAX_VOICE_COUNT=4 STEAL_COUNT=4294967295 SAMPLE_RATE=48000");
        if(session) $fatal(1,"STATUS reactivated session");
        send("NOTE_ON 60 100 0\n"); expect_line("ERROR 0 NOT_READY");
        send("HELLO\n"); expect_line("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE");
        send("NOTE_ON 72 100 0\n"); if(events!=5 || !session) $fatal(1,"HELLO recovery");
        $display("PASS tb_uart_protocol: real UART handshake, notes, decimal, overflow, watchdog"); $finish;
    end
    initial begin #30000000; $fatal(1,"protocol timeout nr=%d line=%s",nr,line); end
endmodule
