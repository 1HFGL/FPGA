`timescale 1ns/1ps

module mixer4_case #(parameter integer SHIFT=0) (output reg done=0);
    reg clk=0, rst=1, valid=0;
    reg [63:0] values=0;
    wire signed [15:0] sample;
    wire out_valid, clipped;
    integer expected=0, total, scaled, checks=0, positive_clip=0, negative_clip=0;
    integer i, v;
    reg expected_valid, expected_clip;
    reg [31:0] random_state=32'h614d91b7;
    always #5 clk=~clk;
    sample_mixer4 #(.MIX_SHIFT(SHIFT)) dut (
        .clk(clk),.rst(rst),.in_valid(valid),.samples_flat(values),
        .sample_out(sample),.out_valid(out_valid),.clipped(clipped)
    );
    // 独立整数参考：循环求和，不复用 RTL 的扩位/两级加法表达式。
    always @(posedge clk) if(!done) begin
        expected_valid=!rst && valid;
        expected_clip=0;
        if(rst) expected=0;
        else if(valid) begin
            total=0;
            for(integer k=0;k<4;k=k+1) total=total+$signed(values[k*16 +: 16]);
            scaled=$rtoi($floor(total*1.0/(2.0**SHIFT)));
            if(scaled>32767) begin expected=32767; expected_clip=1; end
            else if(scaled< -32768) begin expected= -32768; expected_clip=1; end
            else expected=scaled;
        end
        #1;
        if($signed(sample)!==expected || out_valid!==expected_valid || clipped!==expected_clip)
            $fatal(1,"mixer SHIFT=%0d check=%0d actual=%0d expected=%0d valid=%b/%b clip=%b/%b",
                   SHIFT,checks,$signed(sample),expected,out_valid,expected_valid,clipped,expected_clip);
        checks=checks+1;
        if(out_valid && clipped && sample>0) positive_clip++;
        if(out_valid && clipped && sample<0) negative_clip++;
    end
    task cycle(input bit r, input bit en, input logic [63:0] data);
        @(negedge clk); rst=r; valid=en; values=data;
        @(posedge clk); #2;
    endtask
    initial begin
        cycle(1,1,{4{16'h8000}}); // 复位压过有效输入
        // 所有 16 种满幅正负组合，包括四路 -32768、相消和符号边界。
        for(i=0;i<16;i++) begin
            for(v=0;v<4;v++) values[v*16 +: 16]=i[v]?16'h7fff:16'h8000;
            cycle(0,1,values);
        end
        cycle(0,1,64'h000000000000ffff); // -1 右移仍为 -1
        cycle(0,1,64'h0000000000007fff);
        cycle(0,1,64'h0000000000008000);
        cycle(0,1,64'h0000000000017fff); // 32768：正向刚越界
        cycle(0,1,64'h00000000ffff8000); // -32769：负向刚越界
        for(i=0;i<5000;i++) begin
            random_state=random_state*32'd1664525+32'd1013904223;
            cycle(i%997==0,random_state[30],
                  {random_state,random_state^32'hac159de7});
        end
        cycle(0,0,64'd0); // 无效拍保持样本，valid/clip 为 0
        cycle(1,1,64'hffffffffffffffff);
        if(SHIFT==0 && (positive_clip==0 || negative_clip==0)) $fatal(1,"missing saturation coverage");
        if(SHIFT==5 && (positive_clip!=0 || negative_clip!=0)) $fatal(1,"quiet mix unexpectedly clipped");
        $display("mixer SHIFT=%0d verified %0d clocks, clips +%0d/-%0d",
                 SHIFT,checks,positive_clip,negative_clip);
        done=1;
    end
endmodule

module tb_sample_mixer4;
    wire full_done, quiet_done;
    mixer4_case #(.SHIFT(0)) full_case(full_done);
    mixer4_case #(.SHIFT(5)) quiet_case(quiet_done);
    initial begin
        wait(full_done && quiet_done);
        #3; $display("PASS: sample_mixer4 signed boundaries, saturation, idle and reset.");
        $finish;
    end
    initial begin #1000000; $fatal(1,"mixer timeout"); end
endmodule
