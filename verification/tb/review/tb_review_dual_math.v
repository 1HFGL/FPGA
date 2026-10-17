`timescale 1ns/1ps
// 固定亮度乘法的独立64位参考，覆盖实际0..8192年龄和32位参数极值。
module tb_review_dual_math;
    reg clk=0,rst=1;
    reg [13:0] age=0;
    reg [31:0] wide_age=0;
    integer i,checks=0;
    reg [63:0] expected_g,expected_s;
    voice_instrument dut(.clk(clk),.rst(rst),.sample_tick(1'b0),.phase_inc(32'd0),
        .gate(1'b0),.retrigger(1'b0),.instrument(1'b0),.sample(),.sample_valid(),
        .env_level(),.tone_level(),.voice_active(),.active_instrument());
    voice_instrument #(.G_TONE_SAMPLES(32'hffffffff),.S_TONE_SAMPLES(32'h80000001)) wide(
        .clk(clk),.rst(rst),.sample_tick(1'b0),.phase_inc(32'd0),
        .gate(1'b0),.retrigger(1'b0),.instrument(1'b0),.sample(),.sample_valid(),
        .env_level(),.tone_level(),.voice_active(),.active_instrument());
    always #10 clk=~clk;
    initial begin
        repeat(3)@(negedge clk);rst=0;
        force dut.tone_age=age;force wide.tone_age=wide_age;
        for(i=0;i<=8192;i=i+1)begin
            age=i;#1;expected_g=64'd61440*age;expected_s=64'd24576*age;
            if(dut.guitar_product!==expected_g || dut.strings_product!==expected_s ||
               dut.tone_level!==(17'd65536-(expected_g/8192)))begin
                $display("FAIL dual brightness arithmetic age=%0d",i);$finish;
            end
            checks=checks+1;
        end
        for(i=0;i<4;i=i+1)begin
            case(i)0:wide_age=0;1:wide_age=1;2:wide_age=32'h80000000;default:wide_age=32'hffffffff;endcase
            #1;expected_g=64'd61440*wide_age;expected_s=64'd24576*wide_age;
            if(wide.guitar_product!==expected_g || wide.strings_product!==expected_s)begin
                $display("FAIL dual brightness width age=%h",wide_age);$finish;
            end
        end
        $display("PASS tb_review_dual_math: 8193 ages, independent 64-bit multiplication, 32-bit parameter extremes");$finish;
    end
    initial begin #50000;$display("FAIL dual math timeout");$finish;end
endmodule
