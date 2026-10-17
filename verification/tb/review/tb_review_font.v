`timescale 1ns/1ps
// 参考保留整字形，按二维坐标独立寻址；被测实现改为字符/行译码。
module tb_review_font;
    reg [5:0] glyph=0;
    reg [4:0] row=0,column=0;
    reg clk=0;
    wire ink,ink_sync;
    reg [575:0] reference [0:63];
    reg expected;
    integer g,r,c,checks=0;
    always #5 clk=~clk;
    display_font24 dut(.pixel_clk(1'b0),.glyph_id(glyph),.column(column),.row(row),.ink(ink));
    display_font24 #(.SYNCHRONOUS(1)) sync_dut(.pixel_clk(clk),.glyph_id(glyph),.column(column),.row(row),.ink(ink_sync));
    initial begin
        $readmemh("verification/data/display_font_golden.mem",reference);
        for(g=0;g<64;g=g+1)for(r=0;r<32;r=r+1)for(c=0;c<32;c=c+1)begin
            @(negedge clk);glyph=g[5:0];row=r[4:0];column=c[4:0];
            @(posedge clk);#1;
            expected=(r<24 && c<24)?reference[g][575-r*24-c]:1'b0;
            if(ink!==expected || ink_sync!==expected)begin $display("FAIL font glyph=%0d row=%0d column=%0d",g,r,c);$finish;end
            checks=checks+1;
        end
        $display("PASS tb_review_font: %0d glyph/row/column positions including blank bounds",checks);$finish;
    end
endmodule
