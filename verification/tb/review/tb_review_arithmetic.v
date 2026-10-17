`timescale 1ns/1ps
// 覆盖全部7位旋钮值；参考保留原乘除公式，独立检查精确化简及端点。
module tb_review_arithmetic;
    reg clk=0;
    reg [6:0] knob=0;
    wire signed [15:0] bend;
    piano_controls gain_dut(.clk(clk),.rst_n(1'b0),.sample_request(1'b0),
        .knob_value_flat({7'd64,knob}),.knob_valid(1'b0),.param_ready(1'b0),.param_fault(1'b0),
        .master_gain(),.bend_ratio());
    display_bend_map bend_dut(.knob(knob),.bend(bend));
    always #5 clk=~clk;
    integer i,expected_gain,expected_bend,checks=0;
    initial begin
        for(i=0;i<128;i=i+1) begin
            knob=i[6:0];#1;
            expected_gain=(i*65536+63)/127;
            expected_bend=(i<64)?-((63-i)*32767/63):((i-64)*32767/63);
            if(i==0)expected_bend=-32768;
            if(gain_dut.mapped_gain!==expected_gain || $signed(bend)!==expected_bend) begin
                $display("FAIL mapping knob=%0d gain=%0d/%0d bend=%0d/%0d",i,gain_dut.mapped_gain,expected_gain,bend,expected_bend);$finish;
            end
            checks=checks+2;
        end
        $display("PASS tb_review_arithmetic: %0d exact gain/bend values, endpoints and center",checks);$finish;
    end
endmodule
