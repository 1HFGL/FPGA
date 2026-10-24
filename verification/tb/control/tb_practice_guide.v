`timescale 1ns/1ps
module tb_practice_guide;
    reg clk=0,rst_n=0,on=0;
    reg [6:0] note=0;
    reg [1:0] octave=1;
    wire valid,complete;
    wire [3:0] index,progress;
    wire [6:0] target;
    practice_guide dut(.clk(clk),.rst_n(rst_n),.note_on(on),.played_note(note),.octave(octave),
        .target_valid(valid),.target_index(index),.target_note(target),.progress(progress),.complete(complete));
    always #10 clk=~clk;
    integer n,r,base,count=0;
    reg [3:0] melody[0:13];
    task pulse;
        input [6:0] value;
        begin @(negedge clk);note=value;on=1;@(negedge clk);on=0;end
    endtask
    initial begin
        melody[0]=0;melody[1]=0;melody[2]=7;melody[3]=7;melody[4]=9;melody[5]=9;melody[6]=7;
        melody[7]=5;melody[8]=5;melody[9]=4;melody[10]=4;melody[11]=2;melody[12]=2;melody[13]=0;
        for(r=0;r<3;r=r+1)begin
            rst_n=0;repeat(3)@(negedge clk);octave=r;rst_n=1;#1;
            base=48+r*12;
            for(n=0;n<14;n=n+1)begin
                if(!valid || complete || progress!==n+1 || index!==melody[n] || target!==base+melody[n])begin
                    $display("FAIL guide expected step=%0d range=%0d got progress=%0d target=%0d",n,r,progress,target);$stop;end
                pulse(base+1); // 错音仍可正常演奏，但不能推进导奏。
                if(progress!==n+1)begin $display("FAIL guide wrong note advanced");$stop;end
                note=base+melody[n];repeat(12)@(negedge clk);
                if(progress!==n+1)begin $display("FAIL guide held level advanced");$stop;end
                pulse(base+melody[n]);count=count+1;
            end
            if(valid || !complete || progress!=14)begin $display("FAIL guide completion");$stop;end
            pulse(base);pulse(base+7);
            if(valid || progress!=14)begin $display("FAIL guide advanced after completion");$stop;end
        end
        rst_n=0;repeat(3)@(negedge clk);rst_n=1;octave=1;
        pulse(60);octave=2;#1;
        if(progress!=2 || target!=72)begin $display("FAIL guide range changed progress");$stop;end
        pulse(60);if(progress!=2)begin $display("FAIL guide old octave accepted");$stop;end
        pulse(72);if(progress!=3 || target!=79)begin $display("FAIL guide new octave");$stop;end
        $display("PASS tb_practice_guide: 42 correct notes; wrong/held/repeated/completion/reset/octave isolation");$finish;
    end
    initial begin #1000000;$display("FAIL guide timeout");$stop;end
endmodule
