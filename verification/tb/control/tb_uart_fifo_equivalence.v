`timescale 1ns/1ps
// 与固定Git原版和独立队列模型对照；覆盖满队同拍进出、单字替换、flush及复位。
module fifo_equivalence_case #(parameter W=8,A=6)(output reg done=0);
    reg clk=0,rst_n=0,flush=0,iv=0,orr=0;
    reg [W-1:0] data=0;
    wire ir,ov,ref_ir,ref_ov;
    wire [W-1:0] od,ref_od;
    wire [A:0] level,ref_level;
    uart_fifo #(.WIDTH(W),.ADDR_BITS(A)) dut(clk,rst_n,flush,iv,ir,data,ov,orr,od,level);
    uart_fifo_reference #(.WIDTH(W),.ADDR_BITS(A)) ref_fifo(clk,rst_n,flush,iv,ref_ir,data,ref_ov,orr,ref_od,ref_level);
    reg [W-1:0] expected[0:(1<<A)-1];
    integer head=0,tail=0,count=0,cycle=0,pushes=0,pops=0,full_replace=0,single_replace=0;
    reg [31:0] rng=32'hc1376485;
    reg push,pop;
    always #5 clk=~clk;
    always @(posedge clk)begin
        if({ir,ov,level}!=={ref_ir,ref_ov,ref_level} || (ov && od!==ref_od))begin
            $display("FAIL fifo differential W=%0d A=%0d cycle=%0d",W,A,cycle);$stop;
        end
        if(rst_n && !flush)begin
            if(level!==count || ov!==(count!=0))begin $display("FAIL fifo count");$stop;end
            if(ov && od!==expected[head])begin $display("FAIL fifo scoreboard");$stop;end
        end
        push=iv && ir;pop=ov && orr;
        if(!rst_n || flush)begin head=0;tail=0;count=0;end
        else begin
            if(push && pop && count==(1<<A))full_replace=full_replace+1;
            if(push && pop && count==1)single_replace=single_replace+1;
            if(pop)begin head=(head+1)%(1<<A);pops=pops+1;end
            if(push)begin expected[tail]=data;tail=(tail+1)%(1<<A);pushes=pushes+1;end
            count=count+push-pop;
        end
    end
    initial begin
        #2;rst_n=0;#11;rst_n=1;
        for(cycle=0;cycle<60000;cycle=cycle+1)begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            data=rng;flush=0;rst_n=1;
            case((cycle/200)%8)
                0:begin iv=1;orr=0;end
                1:begin iv=1;orr=1;end
                2:begin iv=0;orr=1;end
                3:begin iv=1;orr=1;end
                default:begin iv=rng[3];orr=rng[14];flush=(rng[12:4]==9'h1ff);end
            endcase
            if(cycle%997==0)begin #2;rst_n=0;end
        end
        @(negedge clk);iv=0;orr=1;flush=0;rst_n=1;
        repeat(130)@(negedge clk);
        if(pushes<1000 || pops<1000 || full_replace<100 || single_replace<100)begin
            $display("FAIL fifo coverage");$stop;
        end
        $display("PASS fifo case W=%0d A=%0d push=%0d pop=%0d full_replace=%0d single_replace=%0d",W,A,pushes,pops,full_replace,single_replace);
        done=1;
    end
endmodule
module tb_uart_fifo_equivalence;
    wire a,b,c;
    fifo_equivalence_case #(8,6) rx(a);
    fifo_equivalence_case #(15,4) events(b);
    fifo_equivalence_case #(3,1) tiny(c);
    initial begin wait(a && b && c);$display("PASS tb_uart_fifo_equivalence");$finish;end
    initial begin #1000000;$display("FAIL fifo timeout");$stop;end
endmodule
