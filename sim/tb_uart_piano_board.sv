`timescale 1ns/1ps
// 真实wrapper、50MHz/48kHz、434拍/位、默认ADSR；KEY和串口共享四声部。
module tb_uart_piano_board;
    reg clk=0,rst=0,rx=1;
    reg [1:0] keys=3;
    wire tx,bck,ws,din,pa;
    wire [7:0] reply_byte;
    wire reply_valid,reply_bad;
    integer frames=0,words=0,bits=0,total=0,nonzero=0,cycle=0,request_at=0,j;
    reg [15:0] previous=0,received=0,expected[0:16383];
    string reply="";
    reg hello_seen=0;
    always #10 clk=~clk;
    instrument_uart_piano_top #(.DEBOUNCE_CYCLES(4),.ROM_FILE("rtl/rom/piano_1024.mem")) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(keys),.uart_rx(rx),.uart_tx(tx),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    uart_rx monitor(.clk(clk),.rst_n(rst),.rx(tx),.data(reply_byte),.valid(reply_valid),.frame_error(reply_bad));
    always @(posedge clk) begin
        cycle=cycle+1;
        if(reply_bad) $fatal(1,"bad reply framing");
        if(reply_valid) begin
            if(reply_byte==10) begin
                if(reply!="SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-piano-v1 TONE=FIXED_PIANO")
                    $fatal(1,"wrong piano identity: %s",reply);
                hello_seen=1; reply="";
            end else reply={reply,reply_byte};
        end
        if(!dut.u_core.audio_ready) begin frames=0; previous=0; request_at=0; end
        else begin
            if(dut.u_core.sample_request) begin
                if(frames==16384) $fatal(1,"scoreboard overflow");
                expected[frames]=previous; frames=frames+1; request_at=cycle;
            end
            if(dut.u_core.sample_valid) begin
                if(cycle-request_at!=4 || dut.u_core.sample_clipped!==0) $fatal(1,"R4/clipping");
                previous=dut.u_core.sample_data;
            end
        end
    end
    always @(posedge bck or negedge rst) begin
        if(!rst) begin words=0; bits=0; received=0; end
        else if(dut.u_core.audio_ready) begin
            if(ws!==(words%2) || dut.u_core.sample_underrun!==(words<2)) $fatal(1,"channel/underrun");
            received={received[14:0],din}; bits=bits+1;
            if(bits==16) begin
                if(received!==expected[words/2]) $fatal(1,"DAC word mismatch %0d",words);
                if(received!=0) nonzero=nonzero+1;
                words=words+1; total=total+1; bits=0;
            end
        end
    end
    task send(input string text);
        integer a,b;
        begin
            for(a=0;a<text.len();a=a+1) begin
                @(negedge clk); rx=0; repeat(434) @(negedge clk);
                for(b=0;b<8;b=b+1) begin rx=(text[a]>>b)&1; repeat(434) @(negedge clk); end
                rx=1; repeat(434) @(negedge clk);
            end
            repeat(20) @(negedge clk);
        end
    endtask
    task wait_frames(input integer count);
        integer start;
        begin start=frames; wait(frames>=start+count); @(negedge clk); end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=1; wait_frames(5);
        if(pa!==1) $fatal(1,"idle");
        send("HELLO\n"); wait(hello_seen); @(negedge clk);
        send("NOTE_ON 60 100 0\n"); send("NOTE_ON 64 100 0\n");
        send("NOTE_ON 67 100 0\n"); send("NOTE_ON 72 100 0\n"); wait_frames(150);
        if(dut.u_core.voice_count!=4 || dut.u_core.voice_gate!=15 || pa!==0) $fatal(1,"piano four notes");
        send("PANIC\n"); wait_frames(5);
        if(dut.u_core.voice_gate!=0 || dut.u_core.voice_count==0 || pa!==0) $fatal(1,"missing 180ms tail");
        wait_frames(8650);
        if(dut.u_core.voice_count!=0 || pa!==1) $fatal(1,"piano tail stuck");
        keys=2; wait_frames(150);
        if(dut.u_core.voice_count!=1 || pa!==0) $fatal(1,"physical piano key");
        rst=0; #1; if(tx!==1 || pa!==1) $fatal(1,"midnote reset");
        keys=3; repeat(5) @(negedge clk); rst=1; wait_frames(10);
        if(dut.u_core.session_ready || dut.u_core.voice_count!=0 || pa!==1) $fatal(1,"reset state");
        if(total<17000 || nonzero<1000) $fatal(1,"insufficient audio checks");
        $display("PASS tb_uart_piano_board: real115200 HELLO, four voices, 180ms tail, KEY/reset, %0d DAC words",total);
        $finish;
    end
    initial begin #300000000; $fatal(1,"piano board timeout"); end
endmodule
