`timescale 1ns/1ps
// 整数参考模型直接累计实际发送字符的1/0差，不复用RTL的偏差更新表达式。
module tb_tmds_encoder;
    reg clk=0,rst=0,de=0;
    reg [7:0] data=0;
    reg [1:0] control=0;
    wire [9:0] symbol;
    always #5 clk=~clk;
    tmds_encoder dut(.pixel_clk(clk),.rst_n(rst),.data(data),.de(de),.control(control),.symbol(symbol));
    integer rd=0,n,k,j,test_count=0,seed=32'h12345678,ones;
    reg [9:0] pending=10'b1101010100,expected;
    reg [7:0] transitions,decoded;
    reg xn,invert;
    task step;
        input enable;
        input [7:0] value;
        input [1:0] ctrl;
        begin
            @(negedge clk);de=enable;data=value;control=ctrl;
            if(!enable) begin
                case(ctrl)
                    0:expected=10'b1101010100;1:expected=10'b0010101011;
                    2:expected=10'b0101010100;default:expected=10'b1010101011;
                endcase
                rd=0;
            end else begin
                n=0;for(k=0;k<8;k=k+1)n=n+value[k];
                xn=(n>4 || (n==4 && value[0]==0));
                transitions[0]=value[0];
                for(k=1;k<8;k=k+1)transitions[k]=transitions[k-1]^value[k]^xn;
                n=0;for(k=0;k<8;k=k+1)n=n+transitions[k];
                if(rd==0 || n==4)invert=xn;
                else invert=(rd>0 && n>4)||(rd<0 && n<4);
                expected={invert,!xn,transitions^{8{invert}}};
                ones=0;for(k=0;k<10;k=k+1)ones=ones+expected[k];
                rd=rd+2*ones-10;
                if(rd < -8 || rd > 8)begin $display("FAIL reference disparity %d",rd);$finish;end
                decoded[0]=expected[0]^expected[9];
                for(k=1;k<8;k=k+1)decoded[k]=expected[k]^expected[k-1]^!expected[8];
                if(decoded!==value)begin $display("FAIL reference decode");$finish;end
            end
            @(posedge clk);#1;
            if(symbol!==pending)begin $display("FAIL TMDS got=%b expected=%b test=%0d",symbol,pending,test_count);$finish;end
            pending=expected;test_count=test_count+1;
        end
    endtask
    initial begin
        #12;rst=1;
        for(j=0;j<1024;j=j+1)begin step(0,0,j[9:8]);step(1,j[7:0],0);end
        for(j=0;j<4096;j=j+1)step(1,$random(seed),0);
        step(0,0,3);step(0,0,0);
        @(negedge clk);rst=0;#1;
        if(symbol!==10'b1101010100)begin $display("FAIL TMDS reset");$finish;end
        @(negedge clk);rst=1;rd=0;pending=10'b1101010100;
        step(1,8'hff,0);step(1,8'h00,0);step(0,0,0);step(0,0,0);
        $display("PASS tb_tmds_encoder: all 256 bytes/control tokens, disparity chains, decode, reset (%0d)",test_count);$finish;
    end
    initial begin #200000;$display("FAIL TMDS timeout");$finish;end
endmodule
