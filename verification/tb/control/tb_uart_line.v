`timescale 1ns/1ps
module tb_uart_line;
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
    reg clk=0,rst=0,v=0,bad=0;
    reg [7:0] data=0;
    wire cv,bl,bn,sv; wire [3:0] op,n; wire [31:0] a,b,c;
    integer commands=0,j;
    always #10 clk=~clk;
    uart_line_rx #(.TIMEOUT_CYCLES(100)) dut(.clk(clk),.rst_n(rst),.byte_valid(v),.byte_data(data),
        .bad_byte(bad),.cmd_valid(cv),.cmd(op),.fields(n),.arg0(a),.arg1(b),.arg2(c),
        .bad_line(bl),.bad_number(bn),.sequence_valid(sv));
    always @(posedge clk) if(cv) commands=commands+1;
    task send(input [8191:0] s);
        integer i;
        begin for(i=0;i<packed_strlen(s);i=i+1) begin
            @(negedge clk); v=1; data=s[(packed_strlen(s)-1-i)*8 +: 8]; @(negedge clk); v=0;
        end #1; end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=1;
        send("  NOTE_ON  60 100 0 \015\n");
        if(!cv || op!=2 || n!=4 || a!=60 || b!=100 || c!=0 || bl || bn)
            begin $display("FAIL: parse note cv=%b op=%d fields=%d args=%d/%d/%d bad=%b/%b",cv,op,n,a,b,c,bl,bn); $finish; end
        send("NOTE_OFF 60"); if(cv) begin $display("FAIL: partial command executed"); $finish; end
        send(" 0\n"); if(op!=3 || n!=3 || bl || bn) begin $display("FAIL: fragmented off"); $finish; end
        send("NOTE_ON 4294967296 100 0\n"); if(!bn) begin $display("FAIL: overflow accepted"); $finish; end
        send("NOTE_ON 00000000000 100 0\n"); if(!bn) begin $display("FAIL: digit count"); $finish; end
        send("APPLY 42 255,0 nonsense\n"); if(op!=6 || a!=42 || !sv || bl) begin $display("FAIL: APPLY sequence"); $finish; end
        send("APPLY nope x\n"); if(sv) begin $display("FAIL: bad sequence"); $finish; end
        send("HELLO\015X\n"); if(!bl) begin $display("FAIL: interior CR"); $finish; end
        send("NOTE_ON\t60 100 0\n"); if(!bl) begin $display("FAIL: control accepted"); $finish; end
        send("HELLO"); for(j=0;j<507;j=j+1) send(" "); send("\n");
        if(bl || op!=1) begin $display("FAIL: 512 rejected"); $finish; end
        send("HELLO"); for(j=0;j<508;j=j+1) send(" "); send("\n");
        if(!bl) begin $display("FAIL: 513 accepted"); $finish; end
        send("NOTE_"); @(negedge clk); bad=1; @(negedge clk); bad=0; send("ON 60 100 0\n");
        if(!bl) begin $display("FAIL: bad frame line not discarded"); $finish; end
        send("HEL"); repeat(120) @(negedge clk); send("HELLO\n");
        if(op!=1 || bl || n!=1) begin $display("FAIL: timeout recovery"); $finish; end
        send("STATUS?\n"); if(op!=5 || bl) begin $display("FAIL: resync"); $finish; end
        send("NOTE_OFF_UNKNOWN\n"); if(op!=0 || bl) begin $display("FAIL: unknown long command must stay unsupported, not truncated"); $finish; end
        repeat(3) @(negedge clk);
        if(commands!=14) begin $display("FAIL: command count %0d",commands); $finish; end
        $display("PASS tb_uart_line: fragmentation, bounds, errors, timeout"); $finish;
    end
    initial begin #200000; begin $display("FAIL: line timeout"); $finish; end end
endmodule
