`timescale 1ns/1ps
module tb_timed_practice;
    reg clk=0,rst=0,cv=0,dv=0,dc=0;
    always #10 clk=~clk;
    reg [3:0] kind=0;
    reg [7:0] value=0;
    wire selected,missing,commit;
    wire [8:0] addr;
    wire [2:0] state;
    wire [7:0] bpm;
    wire [9:0] progress;
    wire [1:0] beat;
    wire [36:0] target;
    reg [36:0] mask;
    reg [15:0] duration;
    integer ms,n,k,expected_note,expected_ticks,quarter_total;
    reg [31:0] saved_phase;
    reg [3:0] notes[0:41];
    timed_practice_guide #(.MS_CYCLES(1)) dut(.clk(clk),.rst_n(rst),.command_valid(cv),
        .command_kind(kind),.command_value(value),.download_valid(dv),.download_committed(dc),
        .download_count(10'd3),.download_bpm(8'd120),.read_index(addr),.read_mask(mask),.read_duration(duration),
        .selected_download(selected),.state(state),.bpm(bpm),.progress(progress),.beat(beat),.target(target),
        .missing_download(missing),.can_commit(commit));
    always @(posedge clk)begin mask<=addr==0?37'd3:addr==1?37'd0:37'h1000000000;duration<=addr==1?16'd1:16'd96;end
    task step;begin @(posedge clk);#1;end endtask
    task cmd;input [3:0] a;input [7:0] b;begin @(negedge clk);cv=1;kind=a;value=b;step;@(negedge clk);cv=0;end endtask
    task require;input ok;input [511:0] msg;begin if(ok!==1'b1)begin $display("FAIL %s",msg);$finish(1);end end endtask
    initial begin
        notes[0]=0;notes[1]=0;notes[2]=7;notes[3]=7;notes[4]=9;notes[5]=9;notes[6]=7;
        notes[7]=5;notes[8]=5;notes[9]=4;notes[10]=4;notes[11]=2;notes[12]=2;notes[13]=0;
        notes[14]=7;notes[15]=7;notes[16]=5;notes[17]=5;notes[18]=4;notes[19]=4;notes[20]=2;
        for(k=0;k<7;k=k+1)notes[21+k]=notes[14+k];
        for(k=0;k<14;k=k+1)notes[28+k]=notes[k];
        repeat(3)step;rst=1;step;
        cmd(7,0);require(missing && !selected && state==0,"empty download changes selection");
        for(k=0;k<3;k=k+1)begin
            cmd(8,k==0?30:k==1?90:240);cmd(6,0);
            ms=0;while(state==1 && ms<9000)begin step;ms=ms+1;end
            require(ms==(240000+bpm-1)/bpm,"count-in is not four beats");
            require(state==2 && target==(37'd1<<12),"first target missing");
            saved_phase=dut.phase;cmd(4,0);saved_phase=dut.phase;
            repeat(20)step;require(state==3 && dut.phase==saved_phase,"pause advances phase");
            cmd(4,0);require(state==2,"resume fails");cmd(6,0);require(state==0 && target==0,"K8 fails reset");
        end
        cmd(8,240);cmd(6,0);while(state==1)step;
        n=0;ms=0;
        while(state==2 && ms<13000)begin
            require(progress<42,"builtin index overflow");
            require(target==(37'd1<<(12+notes[progress])),"builtin melody mismatch");
            step;ms=ms+1;
        end
        require(state==4 && progress==42,"builtin never completes");
        dv=1;cmd(7,0);require(selected && bpm==120 && state==0,"K7 download selection");
        cmd(6,0);while(state==1)step;
        require(target==3,"download chord");while(progress==0)step;
        require(target==0,"download rest");while(progress==1)step;
        require(target==37'h1000000000,"download high C");while(state==2)step;
        require(progress==3 && commit,"download end");
        cmd(7,0);require(!selected && bpm==90 && state==0,"builtin selection");
        cmd(6,0);repeat(10)step;cmd(6,0);require(state==0 && progress==0,"count-in reset");
        $display("PASS tb_timed_practice: 3 tempos, complete 42-note score, chord/rest, selection/pause/reset");$finish;
    end
    initial begin #10000000;$display("FAIL timed practice timeout");$finish(1);end
endmodule
