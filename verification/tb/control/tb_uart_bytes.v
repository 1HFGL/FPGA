`timescale 1ns/1ps
// 真正的位级输入；不绕过RX。每个字节均与送入值核对。
module tb_uart_bytes;
    reg clk=0,rst_n=0,rx=1,valid=0;
    reg [7:0] data=0;
    wire tx,ready,rv,err,lv,le;
    wire [7:0] rd,ld;
    integer count=0,errors=0,loop_count=0,i;
    reg [7:0] expected=0;
    always #10 clk=~clk;
    uart_rx #(.CLKS_PER_BIT(434)) dut(.clk(clk),.rst_n(rst_n),.rx(rx),.data(rd),.valid(rv),.frame_error(err));
    uart_tx #(.CLKS_PER_BIT(434)) sender(.clk(clk),.rst_n(rst_n),.data(data),.valid(valid),.ready(ready),.tx(tx));
    uart_rx #(.CLKS_PER_BIT(434)) loopback(.clk(clk),.rst_n(rst_n),.rx(tx),.data(ld),.valid(lv),.frame_error(le));
    always @(posedge clk) begin
        if(rv) begin
`ifdef UART_NEGATIVE_CONTROL
            if((rd^8'h01)!==expected) begin $display("FAIL: intentional byte checker mutation"); $finish; end
`else
            if(rd!==expected) begin $display("FAIL: byte got %h expected %h",rd,expected); $finish; end
`endif
            count=count+1;
        end
        if(err) errors=errors+1;
        if(lv) begin if(ld!==data) begin $display("FAIL: TX loopback mismatch"); $finish; end loop_count=loop_count+1; end
        if(le) begin $display("FAIL: TX bad stop"); $finish; end
    end
    task send_byte(input [7:0] value,input integer period,input stop_ok);
        integer b;
        begin
            expected=value;
            rx=0; #(period);
            for(b=0;b<8;b=b+1) begin rx=value[b]; #(period); end
            rx=stop_ok; #(period); rx=1;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        for(i=0;i<256;i=i+1) begin
            #(i%19+1); send_byte(i[7:0],8680,1);
        end
        send_byte(8'h55,8593,1); send_byte(8'ha6,8767,1);
        repeat(10) @(negedge clk);
        if(count!=258) begin $display("FAIL: RX lost bytes %0d",count); $finish; end
        // 短于半位的低脉冲不能被识别成字节。
        rx=0; #1000; rx=1; #90000;
        if(count!=258) begin $display("FAIL: false start accepted"); $finish; end
        send_byte(8'h13,8680,0); #30000;
        if(errors!=1 || count!=258) begin $display("FAIL: bad stop not rejected"); $finish; end
        for(i=0;i<256;i=i+1) begin
            wait(ready); @(negedge clk); data=i[7:0]; valid=1;
            @(negedge clk); valid=0;
            wait(lv); @(negedge clk); wait(ready);
        end
        if(loop_count!=256) begin $display("FAIL: TX lost bytes"); $finish; end
        // 复位打断起始、数据和停止阶段，恢复后不得提交半帧。
        for(i=0;i<3;i=i+1) begin
            rx=0;
            if(i==0) #1000; else if(i==1) #35000; else #80000;
            rst_n=0; rx=1;
            repeat(5) @(negedge clk);
            if(tx!==1) begin $display("FAIL: TX unsafe reset"); $finish; end
            rst_n=1; #100000;
        end
        if(count!=258) begin $display("FAIL: reset partial frame emitted"); $finish; end
        send_byte(8'h9b,8680,1); #10000;
        if(count!=259) begin $display("FAIL: reset recovery failed"); $finish; end
        $display("PASS tb_uart_bytes: 256 RX/TX values, phase, baud, framing, reset"); $finish;
    end
    initial begin #60000000; begin $display("FAIL: byte timeout"); $finish; end end
endmodule
