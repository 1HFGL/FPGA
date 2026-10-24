`timescale 1ns/1ps
module tb_brightness_response;
    reg clk=0,rst_n=0,valid=0,capture=1;
    reg signed [15:0] x=0;
    reg [6:0] brightness=127;
    wire signed [15:0] y,old_y;
    wire ov,old_valid,tail,overrun;
    reg signed [15:0] captured_old;
    integer fi,fo,rc,n=0,seen=0,xv,bv,gap,reset_flag,segment,cycle=0,due=-1;
    tone_filter_expressive dut(.clk(clk),.rst_n(rst_n),.in_valid(valid),.sample_in(x),
        .brightness(brightness),.sample_out(y),.out_valid(ov),.tail_active(tail),.overrun(overrun));
    tone_filter legacy(.clk(clk),.rst_n(rst_n),.in_valid(valid),.sample_in(x),
        .brightness(brightness),.sample_out(old_y),.out_valid(old_valid),.tail_active(),.overrun());
    always #10 clk=~clk;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!rst_n)due=-1;
        else if(valid)due=cycle+5;
        #1;
        if(old_valid)captured_old=old_y;
        if(rst_n && ov && capture)begin
            if(cycle!=due || overrun)begin $display("FAIL brightness latency/overrun");$finish;end
            $fwrite(fo,"%0d,%0d,%0d\n",seen,$signed(y),$signed(captured_old));seen=seen+1;
        end
        if(rst_n && due==cycle && !ov && capture)begin $display("FAIL brightness missing valid");$finish;end
    end
    initial begin
        fi=$fopen("build/brightness_response/vectors.txt","r");
        fo=$fopen("build/brightness_response/actual.csv","w");
        if(!fi || !fo)begin $display("FAIL brightness files");$finish;end
        $fwrite(fo,"index,new,old\n");
        repeat(3)@(negedge clk);rst_n=1;
        while(!$feof(fi))begin
            rc=$fscanf(fi,"%d %d %d %d %d\n",xv,bv,gap,reset_flag,segment);
            if(rc==5)begin
                if(reset_flag)begin rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
                x=xv;brightness=bv;valid=1;@(negedge clk);valid=0;
                // Must not let the live control affect the second pole of this sample.
                brightness=brightness^7'd127;
                repeat(gap-1)@(negedge clk);n=n+1;
            end
        end
        repeat(8)@(negedge clk);
        if(n!=seen || tail || overrun)begin $display("FAIL brightness count/silence");$finish;end
        capture=0;x=25000;brightness=0;valid=1;@(negedge clk);valid=0;
        rst_n=0;repeat(7)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
        if(ov || tail || y!=0 || overrun)begin $display("FAIL brightness pending reset");$finish;end
        valid=1;repeat(2)@(negedge clk);valid=0;repeat(9)@(negedge clk);
        if(!overrun)begin $display("FAIL brightness overrun not detected");$finish;end
        $fclose(fi);$fclose(fo);
        $display("PASS tb_brightness_response: %0d samples, R5, live-control snapshot, pending reset and overrun",n);$finish;
    end
    initial begin #100000000;$display("FAIL brightness timeout");$finish;end
endmodule
