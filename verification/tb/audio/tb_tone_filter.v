`timescale 1ns/1ps
module tb_tone_filter;
    reg clk=0,rst_n=0,iv=0;
    reg signed [15:0] x=0;
    reg [6:0] tone=127;
    reg capture=1;
    wire signed [15:0] y;
    wire ov,tail,overrun;
    integer fi,fo,rc,n,gap,reset_flag,index=0,expected_index=0,cycle=0,due=-1;
    integer xv,tv,actual_gap;
    tone_filter dut(.clk(clk),.rst_n(rst_n),.in_valid(iv),.sample_in(x),.brightness(tone),
        .sample_out(y),.out_valid(ov),.tail_active(tail),.overrun(overrun));
    always #10 clk=~clk;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(!rst_n)due=-1;
        else if(iv)due=cycle+2;
        #1;
        if(rst_n && ov && capture) begin
            if(cycle!=due)begin $display("FAIL tone latency");$finish;end
            $fwrite(fo,"%0d,%0d,%0d,%0d\n",expected_index,$signed(y),tail,overrun);
            expected_index=expected_index+1;
        end
        if(rst_n && due==cycle && !ov && capture)begin $display("FAIL missing tone valid");$finish;end
    end
    initial begin
        fi=$fopen("build/expression/tone_vectors.txt","r");
        fo=$fopen("build/expression/tone_actual.csv","w");
        if(!fi || !fo)begin $display("FAIL vector file");$finish;end
        $fwrite(fo,"index,y,tail,overrun\n");
        repeat(3)@(negedge clk);rst_n=1;
        while(!$feof(fi))begin
            rc=$fscanf(fi,"%d %d %d %d\n",xv,tv,gap,reset_flag);
            if(rc==4)begin
                if(reset_flag)begin rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
                x=xv;tone=tv;iv=1;@(negedge clk);iv=0;
                repeat(gap-1)@(negedge clk);
                index=index+1;
            end
        end
        repeat(5)@(negedge clk);
        if(index!=expected_index || overrun)begin $display("FAIL count/overrun");$finish;end
        capture=0;
        // Reset cancels a pending result and clears every state element.
        x=20000;iv=1;@(negedge clk);iv=0;rst_n=0;repeat(4)@(negedge clk);
        if(y!==0 || tail!==0 || ov!==0 || overrun!==0)begin $display("FAIL reset");$finish;end
        rst_n=1;repeat(5)@(negedge clk);
        if(ov!==0)begin $display("FAIL stale output");$finish;end
        // Deliberately violate the stated spacing: it must be visible, not silent.
        iv=1;repeat(2)@(negedge clk);iv=0;repeat(4)@(negedge clk);
        if(overrun!==1)begin $display("FAIL overrun detector");$finish;end
        $fclose(fi);$fclose(fo);
        $display("PASS tb_tone_filter: %0d outputs, R2 valid, reset cancellation, overrun",index);$finish;
    end
    initial begin #100000000;$display("FAIL tone timeout");$finish;end
endmodule
