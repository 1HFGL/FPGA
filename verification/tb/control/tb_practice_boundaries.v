`timescale 1ns/1ps
module tb_practice_boundaries;
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
        repeat(3)step;rst=1;step;
        cmd(8,120);cmd(6,0);
        cmd(9,1);cmd(9,1);cmd(9,1);
        while(beat==0)step;
        require(bpm==135,"successive speed presses must accumulate");
        // 在第四拍最后一个tick前请求暂停，恢复必须继续这一tick。
        while(!(state==1 && beat==3 && dut.tick_in_beat==95 && dut.phase_sum>=60000))begin @(negedge clk);end
        cv=1;kind=4;value=0;saved_phase=dut.phase;step;
        require(state==3 && dut.phase==saved_phase && target==0,"pause/count-in boundary consumes tick");
        @(negedge clk);cv=0;repeat(10)step;cmd(4,0);step;
        require(state==2 && target==(37'd1<<12),"resume skips first target");
        // 最后一段剩一个tick时暂停，恢复后正常完成，不能回RUNNING再多弹一段。
        while(!(state==2 && progress==41 && dut.remaining==1 && dut.phase_sum>=60000))@(negedge clk);
        cv=1;kind=4;step;require(state==3 && progress==41 && target!=0,"pause/final segment consumes target");
        @(negedge clk);cv=0;repeat(10)step;cmd(4,0);step;
        require(state==4 && progress==42 && target==0,"resume fails final completion");
        $display("PASS tb_practice_boundaries: tempo accumulation, exact count-in/end tick pause");$finish;
    end
    initial begin #10000000;$display("FAIL timed practice timeout");$finish(1);end
endmodule
