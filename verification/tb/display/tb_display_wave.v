`timescale 1ns/1ps
module tb_display_wave;
    reg clk=0,rst_n=0,valid=0,commit=0;
    reg [7:0] data=0,addr=0;
    wire [7:0] q;
    wire ready;
    integer i;
    always #5 clk=~clk;
    display_wave_buffer dut(.pixel_clk(clk),.rst_n(rst_n),.sample_valid(valid),
        .sample_data(data),.frame_commit(commit),.read_addr(addr),.read_data(q),.wave_ready(ready));
    task fill;
        input integer offset;
        begin
            for(i=0;i<256;i=i+1) begin @(negedge clk);valid=1;data=(i+offset)&255;end
            @(negedge clk);valid=0;
        end
    endtask
    task swap;
        begin @(negedge clk);commit=1;@(negedge clk);commit=0;end
    endtask
    task verify;
        input integer offset;
        begin
            for(i=0;i<256;i=i+1) begin
                @(negedge clk);addr=i;
                @(posedge clk);#1;
                if(q!==((i+offset)&255)) begin $display("FAIL wave index=%0d q=%0d",i,q);$finish;end
            end
        end
    endtask
    initial begin
        #2;if(q!==0 || ready!==0) begin $display("FAIL wave reset mask");$finish;end
        @(negedge clk);rst_n=1;
        fill(0);
        if(ready!==0 || q!==0) begin $display("FAIL early wave publication");$finish;end
        // 页满后继续来的数据不得覆盖待显示页。
        valid=1;data=77;repeat(20) @(negedge clk);valid=0;
        swap;verify(0);
        fill(91);verify(0); // 第二页写好也不能在帧中途覆盖当前页
        swap;verify(91);
        // 写到半页时复位，首个新页仍必须写满。
        valid=1;repeat(41) @(negedge clk);rst_n=0;valid=0;
        #1;if(q!==0 || ready!==0) begin $display("FAIL wave interrupted reset");$finish;end
        @(negedge clk);rst_n=1;swap;
        if(ready!==0) begin $display("FAIL partial page published");$finish;end
        fill(173);swap;verify(173);
        $display("PASS tb_display_wave: all addresses, frame swaps, no tearing, reset masking");$finish;
    end
    initial begin #1000000;$display("FAIL wave timeout");$finish;end
endmodule
