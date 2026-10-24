`timescale 1ns/1ps
// 只验证新的组合选择结构，不改队友TB。旧实现从固定Git恢复至build。
// 逐拍比较事件顺序/有效/溢出，覆盖回绕、满队列同进同出、旧音松键及复位。
module tb_event_selection_equivalence;
    reg clk=0;
    wire [3:0] done;
    always #5 clk=~clk;
    event_selection_case #(.KEYS(1),.BASE(0)) c0(clk,done[0]);
    event_selection_case #(.KEYS(2),.CHROMATIC(0),.CONTROL(0)) c1(clk,done[1]);
    event_selection_case #(.KEYS(13)) c2(clk,done[2]);
    event_selection_case #(.KEYS(16),.BASE(126)) c3(clk,done[3]);
    initial begin
        wait(&done);
        $display("PASS tb_event_selection_equivalence: 4 key-count cases, 480000 cycles, priority/wrap/backpressure/overflow/octave/held-note/reset");
        $finish;
    end
    initial begin #1300000;$display("FAIL event timeout");$finish;end
endmodule

module event_selection_case #(
    parameter integer KEYS=13,BASE=60,CHROMATIC=1,CONTROL=1
)(input wire clk,output reg done=0);
    reg rst_n=0,ready=0;
    reg [KEYS-1:0] press=0,release_key=0;
    reg [KEYS*7-1:0] velocity=0;
    reg [3:0] timbre=0;
    reg [1:0] octave=1;
    reg [31:0] random_state=32'h6d83b419;
    wire overflow,valid,kind,old_overflow,old_valid,old_kind;
    wire [4:0] source,old_source;
    wire [6:0] note,vel,old_note,old_vel;
    wire [3:0] tone,old_tone;
    integer cycle,k,index,events=0,stalls=0,faults=0,drains=0;
    event_encoder #(.KEY_COUNT(KEYS),.NOTE_BASE(BASE),.MAX_EVENTS(16),.PTR_WIDTH(4),
        .SOURCE_WIDTH(5),.CHROMATIC_KEYS(CHROMATIC),.ENABLE_PLAY_CONTROL(CONTROL)) dut(
        clk,rst_n,press,release_key,velocity,timbre,octave,overflow,valid,kind,source,note,vel,tone,ready);
    event_encoder_before #(.KEY_COUNT(KEYS),.NOTE_BASE(BASE),.MAX_EVENTS(16),.PTR_WIDTH(4),
        .SOURCE_WIDTH(5),.CHROMATIC_KEYS(CHROMATIC),.ENABLE_PLAY_CONTROL(CONTROL)) reference(
        clk,rst_n,press,release_key,velocity,timbre,octave,old_overflow,old_valid,old_kind,old_source,old_note,old_vel,old_tone,ready);
    always @(posedge clk)begin
        if(rst_n && !done)begin
            if({overflow,valid} !== {old_overflow,old_valid} ||
                (valid && {kind,source,note,vel,tone} !== {old_kind,old_source,old_note,old_vel,old_tone}) ||
                dut.rr_key !== reference.rr_key || dut.fifo_count !== reference.fifo_count)begin
                $display("FAIL event selection mismatch keys=%0d cycle=%0d",KEYS,cycle);$finish;
            end
            if(valid && ready)events=events+1;
            if(valid && !ready)stalls=stalls+1;
            if(overflow)faults=faults+1;
            if(dut.do_read && dut.do_write)drains=drains+1;
        end
    end
    initial begin
        for(cycle=0;cycle<120000;cycle=cycle+1)begin
            @(negedge clk);
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            press=0;release_key=0;
            rst_n=(cycle%256)!=0;
            ready=(cycle%256>=18 && cycle%256<128) || cycle%256>=240;
            timbre=random_state[3:0];octave=random_state[5:4];
            for(k=0;k<KEYS;k=k+1)velocity[k*7+:7]=(random_state>>(k%19))&127;
            case(cycle%256)
                2:press={KEYS{1'b1}};
                16:release_key={KEYS{1'b1}};
                default:begin
                    if(cycle%256>=61 && cycle%256<240)begin
                        index=random_state[15:8]%KEYS;
                        if(random_state[16])press[index]=1;else release_key[index]=1;
                    end
                end
            endcase
        end
        if(events<50 || stalls==0 || faults==0 || drains==0)begin
            $display("FAIL event coverage keys=%0d events=%0d stalls=%0d faults=%0d concurrent=%0d",KEYS,events,stalls,faults,drains);$finish;
        end
        done=1;
    end
endmodule
