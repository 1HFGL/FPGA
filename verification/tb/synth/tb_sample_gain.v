`timescale 1ns/1ps
module tb_sample_gain;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, in_valid=0;
    reg signed [15:0] sample_in=0;
    reg [16:0] gain=0;
    wire signed [15:0] sample_out;
    wire out_valid;
    integer amplitude, gain_index, checks=0;
    integer gains[0:6];
    integer last_sample=0;
    reg signed [63:0] reference_product;
    integer expected;
    sample_gain dut(.clk(clk), .rst(rst), .in_valid(in_valid),
        .sample_in(sample_in), .gain(gain), .sample_out(sample_out), .out_valid(out_valid));

    task check;
        input r, valid;
        input integer value, coefficient;
        begin
            @(negedge clk);
            rst=r; in_valid=valid; sample_in=value; gain=coefficient;
            if (r) expected=0;
            else if (valid) begin
                reference_product=value;
                reference_product=reference_product*((coefficient>65536)?65536:coefficient);
                // Division plus remainder models floor independently of RTL shift.
                expected=reference_product/65536;
                if (reference_product<0 && reference_product%65536!=0) expected=expected-1;
            end else expected=last_sample;
            @(posedge clk); #1;
            if ($signed(sample_out) !== expected || out_valid !== (valid && !r))
                begin $display("FAIL: Gain mismatch: input=%0d gain=%0d actual=%0d expected=%0d",
                       value, coefficient, $signed(sample_out), expected); $finish; end
            last_sample=expected;
            checks=checks+1;
        end
    endtask
    initial begin
        gains[0]=0; gains[1]=1; gains[2]=32767; gains[3]=32768;
        gains[4]=65535; gains[5]=65536; gains[6]=131071;
        check(1,1,-32768,65536);
        for (gain_index=0; gain_index<7; gain_index=gain_index+1)
            for (amplitude=-32768; amplitude<=32767; amplitude=amplitude+1)
                check(0,1,amplitude,gains[gain_index]);
        check(0,1,-12345,32768);
        check(0,0,22222,0); // idle must hold sample and clear valid
        check(1,1,32767,65536);
        check(0,0,-32768,65536);
        $display("PASS: sample_gain exhaustive checks (%0d).",checks);
        $stop;
    end
    initial begin #10000000; begin $display("FAIL: Gain timeout"); $finish; end end
endmodule
