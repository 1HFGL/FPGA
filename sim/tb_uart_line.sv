`timescale 1ns/1ps
module tb_uart_line;
    reg clk=0,rst=0,v=0,bad=0;
    reg [7:0] data=0;
    wire cv,bl,bn,sv; wire [3:0] op,n; wire [31:0] a,b,c;
    integer commands=0,j;
    always #10 clk=~clk;
    uart_line_rx #(.TIMEOUT_CYCLES(100)) dut(.clk(clk),.rst_n(rst),.byte_valid(v),.byte_data(data),
        .bad_byte(bad),.cmd_valid(cv),.cmd(op),.fields(n),.arg0(a),.arg1(b),.arg2(c),
        .bad_line(bl),.bad_number(bn),.sequence_valid(sv));
    always @(posedge clk) if(cv) commands=commands+1;
    task send(input string s);
        integer i;
        begin for(i=0;i<s.len();i=i+1) begin
            @(negedge clk); v=1; data=s[i]; @(negedge clk); v=0;
        end #1; end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=1;
        send("  NOTE_ON  60 100 0 \015\n");
        if(!cv || op!=2 || n!=4 || a!=60 || b!=100 || c!=0 || bl || bn)
            $fatal(1,"parse note cv=%b op=%d fields=%d args=%d/%d/%d bad=%b/%b",cv,op,n,a,b,c,bl,bn);
        send("NOTE_OFF 60"); if(cv) $fatal(1,"partial command executed");
        send(" 0\n"); if(op!=3 || n!=3 || bl || bn) $fatal(1,"fragmented off");
        send("NOTE_ON 4294967296 100 0\n"); if(!bn) $fatal(1,"overflow accepted");
        send("NOTE_ON 00000000000 100 0\n"); if(!bn) $fatal(1,"digit count");
        send("APPLY 42 255,0 nonsense\n"); if(op!=6 || a!=42 || !sv || bl) $fatal(1,"APPLY sequence");
        send("APPLY nope x\n"); if(sv) $fatal(1,"bad sequence");
        send("HELLO\015X\n"); if(!bl) $fatal(1,"interior CR");
        send("NOTE_ON\t60 100 0\n"); if(!bl) $fatal(1,"control accepted");
        send("HELLO"); for(j=0;j<507;j=j+1) send(" "); send("\n");
        if(bl || op!=1) $fatal(1,"512 rejected");
        send("HELLO"); for(j=0;j<508;j=j+1) send(" "); send("\n");
        if(!bl) $fatal(1,"513 accepted");
        send("NOTE_"); @(negedge clk); bad=1; @(negedge clk); bad=0; send("ON 60 100 0\n");
        if(!bl) $fatal(1,"bad frame line not discarded");
        send("HEL"); repeat(120) @(negedge clk); send("HELLO\n");
        if(op!=1 || bl || n!=1) $fatal(1,"timeout recovery");
        send("STATUS?\n"); if(op!=5 || bl) $fatal(1,"resync");
        send("NOTE_OFF_UNKNOWN\n"); if(op!=0 || bl) $fatal(1,"unknown long command must stay unsupported, not truncated");
        repeat(3) @(negedge clk);
        if(commands!=14) $fatal(1,"command count %0d",commands);
        $display("PASS tb_uart_line: fragmentation, bounds, errors, timeout"); $finish;
    end
    initial begin #200000; $fatal(1,"line timeout"); end
endmodule
