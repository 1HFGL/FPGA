`timescale 1ns/1ps
// 人为放慢TX ready，洪泛HELLO/STATUS/ERROR，检查不会交错或卡住回复。
module tb_uart_replies;
    reg clk=0,rst=0,h=0,s=0,e=0;
    reg [5:0] count=4,peak=4;
    reg [31:0] steals=1,seq=0;
    wire valid; wire [7:0] data;
    integer cycle=0,nr=0,i;
    wire ready=(cycle%8==0);
    string line="",replies[0:63];
    always #10 clk=~clk;
    uart_reply_tx dut(.clk(clk),.rst_n(rst),.hello_req(h),.status_req(s),.error_req(e),
        .voice_count(count),.max_voice_count(peak),.steal_count(steals),.error_sequence(seq),.error_code(3'd5),
        .tx_data(data),.tx_valid(valid),.tx_ready(ready));
    always @(posedge clk) begin
        cycle=cycle+1;
        if(valid && ready) begin
            if(data==10) begin replies[nr]=line; line=""; nr=nr+1; end
            else line={line,data};
        end
    end
    initial begin
        repeat(4) @(negedge clk); rst=1; h=1; @(negedge clk); h=0;
        repeat(30) @(negedge clk);
        for(i=0;i<20;i=i+1) begin
            h=1; s=1; e=1; seq=i;
            @(negedge clk); h=0; s=0; e=0; @(negedge clk);
        end
        count=2; peak=4; steals=1234567890; s=1; @(negedge clk); s=0;
        wait(nr==5); @(negedge clk);
        if(replies[0]!="SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE" || replies[1]!=replies[0])
            $fatal(1,"HELLO interrupted or lost");
        if(replies[2]!="STATUS VOICE_COUNT=2 MAX_VOICE_COUNT=4 STEAL_COUNT=1234567890 SAMPLE_RATE=48000") $fatal(1,"latest STATUS %s",replies[2]);
        if(replies[3]!="ERROR 0 UNSUPPORTED" || replies[4]!="ERROR 1 UNSUPPORTED") $fatal(1,"error slots ordering");
        repeat(100) @(negedge clk); if(nr!=5) $fatal(1,"unbounded duplicates");
        $display("PASS tb_uart_replies: finite slots, HELLO priority, STATUS coalescing, decimal and stalls"); $finish;
    end
    initial begin #300000; $fatal(1,"reply timeout lines=%d partial=%s",nr,line); end
endmodule
