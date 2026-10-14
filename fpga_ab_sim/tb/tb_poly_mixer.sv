`timescale 1ns/1ps
module tb_poly_mixer #(parameter integer N=16);
    reg [N*16-1:0] samples;
    wire signed [15:0] actual;
    integer i, trial;
    reg signed [63:0] total;
    reg signed [15:0] expected;
    reg [31:0] random_state=32'h416db239;
    poly_mixer_saturator #(.VOICES(N)) dut(samples,actual);
    task check;
        begin
            total=0;
            for(i=0;i<N;i=i+1) total=total+$signed(samples[i*16+:16]);
            if(total>32767) expected=32767;
            else if(total< -32768) expected=-32768;
            else expected=total[15:0];
            #1;
            if(actual!==expected) $fatal(1,"FAIL: mixer N=%0d sum=%0d actual=%0d expected=%0d",N,total,actual,expected);
        end
    endtask
    initial begin
        samples=0; check;
        samples={N{16'h7fff}}; check;
        samples={N{16'h8000}}; check;
        for(trial=0;trial<2000;trial=trial+1) begin
            for(i=0;i<N;i=i+1) begin
                random_state=random_state^(random_state<<13);
                random_state=random_state^(random_state>>17);
                random_state=random_state^(random_state<<5);
                samples[i*16+:16]=random_state[15:0];
            end
            check;
        end
        $display("PASS: mixer N=%0d signed summation and saturation",N);
        $finish;
    end
endmodule
module tb_poly_mixer_1; tb_poly_mixer #(.N(1)) test(); endmodule
module tb_poly_mixer_3; tb_poly_mixer #(.N(3)) test(); endmodule
module tb_poly_mixer_32; tb_poly_mixer #(.N(32)) test(); endmodule
