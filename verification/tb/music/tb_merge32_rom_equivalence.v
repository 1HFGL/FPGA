`timescale 1ns/1ps
module tb_merge32_rom_equivalence;
    GSR GSR(.GSRI(1'b1));
    reg clk=0,ea=0,eb=0;
    reg [13:0] aa=0,ab=0;
    reg [6:0] ma=0,mb=0;
    wire [75:0] va,vb,fa,fb;
    integer n,checks=0;
    always #10 clk=~clk;
    modal_coeff_rom_dual_vendor vendor(.clk(clk),.en_a(ea),.en_b(eb),.address_a(aa),.address_b(ab),
        .metadata_a(ma),.metadata_b(mb),.data_a(va),.data_b(vb));
    modal_coeff_rom_dual fast(.clk(clk),.en_a(ea),.en_b(eb),.address_a(aa),.address_b(ab),
        .metadata_a(ma),.metadata_b(mb),.data_a(fa),.data_b(fb));
    task compare;
        begin
            @(posedge clk);#1;
            if(va!==fa || vb!==fb)begin $display("FAIL functional ROM equivalence address=%0d/%0d",aa,ab);$finish;end
            checks=checks+1;@(negedge clk);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);
        for(n=0;n<12288;n=n+1)begin
            aa=n;ab=12287-n;ma=n%96;mb=(n*17)%96;ea=1;eb=1;compare;
            ea=n%2;eb=!(n%2);ma=127;mb=127;compare;
        end
        ea=0;eb=0;repeat(4)compare;
        $display("PASS tb_merge32_rom_equivalence: %0d cycles; all 12288 addresses on both physical DPB ports, independent holds and metadata",checks);$finish;
    end
endmodule
