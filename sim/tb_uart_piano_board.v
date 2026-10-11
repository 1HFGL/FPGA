`timescale 1ns/1ps
// 真实wrapper、50MHz/48kHz、434拍/位、默认ADSR；KEY和串口共享四声部。
module tb_uart_piano_board;
    // Verilog 定长字节向量代替 SV string；测试文本最多 1024 字节，不含内嵌 NUL。
    function integer packed_strlen;
        input [8191:0] value;
        integer k;
        begin
            packed_strlen=0;
            for(k=0;k<1024;k=k+1)
                if(value[k*8 +: 8]!=0) packed_strlen=k+1;
        end
    endfunction
    reg clk=0,rst=0,rx=1;
    reg [1:0] keys=3;
    wire tx,bck,ws,din,pa;
    wire [7:0] reply_byte;
    wire reply_valid,reply_bad;
    integer frames=0,words=0,bits=0,total=0,nonzero=0,cycle=0,request_at=0,j;
    reg [15:0] previous=0,received=0,expected[0:16383];
    reg [8191:0] reply="";
    reg hello_seen=0;
    always #10 clk=~clk;
    instrument_uart_piano_top #(.DEBOUNCE_CYCLES(4),.ROM_FILE("rtl/rom/piano_1024.mem")) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(keys),.uart_rx(rx),.uart_tx(tx),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    uart_rx monitor(.clk(clk),.rst_n(rst),.rx(tx),.data(reply_byte),.valid(reply_valid),.frame_error(reply_bad));
    always @(posedge clk) begin
        cycle=cycle+1;
        if(reply_bad) begin $display("FAIL: bad reply framing"); $finish; end
        if(reply_valid) begin
            if(reply_byte==10) begin
                if(reply!="SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-piano-v1 TONE=FIXED_PIANO")
                    begin $display("FAIL: wrong piano identity: %s",reply); $finish; end
                hello_seen=1; reply="";
            end else reply={reply,reply_byte};
        end
        if(!dut.u_core.audio_ready) begin frames=0; previous=0; request_at=0; end
        else begin
            if(dut.u_core.sample_request) begin
                if(frames==16384) begin $display("FAIL: scoreboard overflow"); $finish; end
                expected[frames]=previous; frames=frames+1; request_at=cycle;
            end
            if(dut.u_core.sample_valid) begin
                if(cycle-request_at!=4 || dut.u_core.sample_clipped!==0) begin $display("FAIL: R4/clipping"); $finish; end
                previous=dut.u_core.sample_data;
            end
        end
    end
    always @(posedge bck or negedge rst) begin
        if(!rst) begin words=0; bits=0; received=0; end
        else if(dut.u_core.audio_ready) begin
            if(ws!==(words%2) || dut.u_core.sample_underrun!==(words<2)) begin $display("FAIL: channel/underrun"); $finish; end
            received={received[14:0],din}; bits=bits+1;
            if(bits==16) begin
                if(received!==expected[words/2]) begin $display("FAIL: DAC word mismatch %0d",words); $finish; end
                if(received!=0) nonzero=nonzero+1;
                words=words+1; total=total+1; bits=0;
            end
        end
    end
    task send(input [8191:0] text);
        integer a,b;
        begin
            for(a=0;a<packed_strlen(text);a=a+1) begin
                @(negedge clk); rx=0; repeat(434) @(negedge clk);
                for(b=0;b<8;b=b+1) begin rx=(text[(packed_strlen(text)-1-a)*8 +: 8]>>b)&1; repeat(434) @(negedge clk); end
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
        if(pa!==1) begin $display("FAIL: idle"); $finish; end
        send("HELLO\n"); wait(hello_seen); @(negedge clk);
        send("NOTE_ON 60 100 0\n"); send("NOTE_ON 64 100 0\n");
        send("NOTE_ON 67 100 0\n"); send("NOTE_ON 72 100 0\n"); wait_frames(150);
        if(dut.u_core.voice_count!=4 || dut.u_core.voice_gate!=15 || pa!==0) begin $display("FAIL: piano four notes"); $finish; end
        send("PANIC\n"); wait_frames(5);
        if(dut.u_core.voice_gate!=0 || dut.u_core.voice_count==0 || pa!==0) begin $display("FAIL: missing 180ms tail"); $finish; end
        wait_frames(8650);
        if(dut.u_core.voice_count!=0 || pa!==1) begin $display("FAIL: piano tail stuck"); $finish; end
        keys=2; wait_frames(150);
        if(dut.u_core.voice_count!=1 || pa!==0) begin $display("FAIL: physical piano key"); $finish; end
        rst=0; #1; if(tx!==1 || pa!==1) begin $display("FAIL: midnote reset"); $finish; end
        keys=3; repeat(5) @(negedge clk); rst=1; wait_frames(10);
        if(dut.u_core.session_ready || dut.u_core.voice_count!=0 || pa!==1) begin $display("FAIL: reset state"); $finish; end
        if(total<17000 || nonzero<1000) begin $display("FAIL: insufficient audio checks"); $finish; end
        $display("PASS tb_uart_piano_board: real115200 HELLO, four voices, 180ms tail, KEY/reset, %0d DAC words",total);
        $finish;
    end
    initial begin #300000000; begin $display("FAIL: piano board timeout"); $finish; end end
endmodule
