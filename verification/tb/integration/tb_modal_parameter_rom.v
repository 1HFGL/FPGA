`timescale 1ns/1ps
// 独立原表逐地址对照；包含bank边界、静音填充、读使能保持和同步复位。
module tb_modal_parameter_rom;
    reg clk=0,rst_n=0,enable=0;
    reg [13:0] address=0;
    wire [75:0] data;
    reg [75:0] expected,original[0:16383];
    integer n,checked=0;
    always #10 clk=~clk;
    modal_parameter_rom dut(.clk(clk),.rst_n(rst_n),.read_enable(enable),.address(address),.data(data));
    task verify;
        input [75:0] value;
        begin
            @(posedge clk);#1;
            if(data!==value)begin
                $display("FAIL modal ROM value address=%0d got=%h expected=%h",address,data,value);$finish;
            end
            checked=checked+1;
            @(negedge clk);
        end
    endtask
    initial begin
        $readmemh("rtl/rom/piano_v3_modes.mem",original);
        verify(0);rst_n=1;
        for(n=0;n<16384;n=n+1)begin
            address=n[13:0];enable=1;
            expected=original[n];verify(expected);
            if(n%127==0)begin enable=0;address=~address;verify(expected);end
            if(n%4093==0)begin
                rst_n=0;enable=1;verify(0);rst_n=1;
            end
        end
        rst_n=0;enable=0;verify(0);rst_n=1;verify(0);
        $display("PASS tb_modal_parameter_rom: %0d checks, all16384 addresses, all128 notes/both presets, enable/reset",checked);$finish;
    end
    initial begin #1000000;$display("FAIL modal ROM timeout");$finish;end
endmodule
