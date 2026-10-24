`timescale 1ns/1ps
// 正式32声部顶层、真实115200波特率：逐字节核对完整握手，复位后重握手。
// 不用打包字符串整体相等掩盖多发NUL，不从DUT取期望容量。
module tb_dual16_uart;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,rst_n=0,rx=1;
    wire tx,bck,ws,din,pa,scl;
    tri1 sda;
    wire [7:0] reply_byte;
    wire reply_valid,reply_bad;
    localparam [8*92-1:0] EXPECTED="SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=32 SAMPLE_RATE=48000 FW=uart-dual-v1 TONE=PIANO_GUITAR\n";
    integer received=0,lines=0,round_no,byte_no,bit_no;
    reg [47:0] hello="HELLO\n";
    always #10 clk=~clk;
    piano_performance_top #(.ROM_FILE("rtl/rom/piano_1024.mem"),.DEBOUNCE_CYCLES(8)) dut(
        .sys_clk(clk),.sys_rst_n(rst_n),.Key_in(2'b11),.piano_key_n(13'h1fff),
        .uart_rx(rx),.uart_tx(tx),.HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),
        .knob_sda(sda),.knob_scl(scl));
    uart_rx #(.CLKS_PER_BIT(434)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),
        .data(reply_byte),.valid(reply_valid),.frame_error(reply_bad));
    always @(posedge clk) begin
        if(!rst_n)begin received=0;lines=0;end
        else begin
            if(reply_bad)begin $display("FAIL capacity top UART framing");$finish;end
            if(reply_valid)begin
                if(received>=92 || reply_byte!==EXPECTED[(91-received)*8+:8])begin
                    $display("FAIL capacity top byte %0d got=%h expected=%h",received,reply_byte,EXPECTED[(91-received)*8+:8]);$finish;
                end
                received=received+1;
                if(reply_byte==10)begin
                    if(received!=92)begin $display("FAIL capacity top length");$finish;end
                    received=0;lines=lines+1;
                end
            end
        end
    end
    initial begin
        for(round_no=0;round_no<2;round_no=round_no+1)begin
            @(negedge clk);rst_n=0;rx=1;repeat(8)@(negedge clk);
            rst_n=1;wait(dut.u_core.audio_ready);repeat(20)@(negedge clk);
            for(byte_no=5;byte_no>=0;byte_no=byte_no-1)begin
                rx=0;repeat(434)@(negedge clk);
                for(bit_no=0;bit_no<8;bit_no=bit_no+1)begin
                    rx=hello[byte_no*8+bit_no];repeat(434)@(negedge clk);
                end
                rx=1;repeat(434)@(negedge clk);
            end
            wait(lines==1);repeat(500)@(negedge clk);
            if(lines!=1 || dut.u_core.voice_count!=0)begin $display("FAIL capacity top duplicate or note side effect");$finish;end
        end
        $display("PASS tb_dual16_uart: production 32 voices, 115200, exact 92 bytes, reset and re-handshake");$finish;
    end
    initial begin #25000000;$display("FAIL capacity top timeout");$finish;end
endmodule
