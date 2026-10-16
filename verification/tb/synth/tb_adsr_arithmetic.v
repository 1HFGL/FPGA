`timescale 1ns/1ps

// 仅用于验证：注入全部合法幅度，参考直接用整数除法，独立于优化结构。
// force 不进入可综合 RTL；完整时序/重触发/参数边界仍由 tb_adsr_env 检查。
module tb_adsr_arithmetic;
    reg clk=0, rst=1, gate=0, retrigger=0;
    reg [16:0] injected_level=0;
    wire [16:0] env_level;
    wire [2:0] state;
    wire active;
    integer level_value, checks=0;
    integer expected_q, expected_r, observed_q;
    always #5 clk=~clk;

    adsr_env dut (.clk(clk),.rst(rst),.sample_tick(1'b0),.gate(gate),
        .retrigger(retrigger),.env_level(env_level),.active(active),.state(state));

    initial begin
        repeat(2) @(negedge clk);
        rst=0;
        force dut.env_level=injected_level;
        for(level_value=0;level_value<=65536;level_value=level_value+1) begin
            injected_level=level_value;
            gate=1; retrigger=1;
            #1;
            expected_q=(65536-level_value)/96;
            expected_r=(65536-level_value)%96;
            observed_q=dut.attack_step;
`ifdef ADSR_ARITH_NEGATIVE_CONTROL
            observed_q=observed_q^1; // 故意污染观察值，验证算术检查器确实能拒绝错误。
`endif
            if(observed_q!==expected_q || dut.attack_rem!==expected_r ||
               dut.next_level!==(level_value+expected_q))
                begin $display("FAIL: ADSR attack arithmetic level=%0d q/r=%0d/%0d expected=%0d/%0d next=%0d",
                    level_value,observed_q,dut.attack_rem,expected_q,expected_r,dut.next_level); $finish; end
            gate=0; retrigger=0;
            #1;
            expected_q=level_value/5760;
            expected_r=level_value%5760;
            if(dut.release_step!==expected_q || dut.release_rem!==expected_r ||
               dut.next_level!==(level_value-expected_q))
                begin $display("FAIL: ADSR release arithmetic level=%0d q/r=%0d/%0d expected=%0d/%0d next=%0d",
                    level_value,dut.release_step,dut.release_rem,expected_q,expected_r,dut.next_level); $finish; end
            checks=checks+2;
        end
        release dut.env_level;
        @(negedge clk); rst=1;
        @(posedge clk); #1;
        if(env_level!==0 || state!==0 || active!==0)
            begin $display("FAIL: ADSR arithmetic post-injection reset failed"); $finish; end
        $display("PASS: adsr arithmetic exhaustive checks (%0d checks, 65537 levels, reset).",checks);
        $finish;
    end
    initial begin #1000000; begin $display("FAIL: ADSR arithmetic timeout"); $finish; end end
endmodule
