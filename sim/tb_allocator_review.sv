`timescale 1ns/1ps

// 参考模型用不会在本次测试内回绕的事件序号判断先后，不复制 RTL 的年龄实现。
module allocator_review_case #(parameter integer MODE = 0)(output reg done = 0);
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;
    reg event_valid = 0, event_type = 0, expr_valid = 0;
    reg [4:0] source = 0, expr_source = 0;
    reg [6:0] note = 0, expr_note = 0;
    reg [15:0] bend = 0;
    wire event_ready, expr_ready;
    wire [3:0] active, gate, trigger;
    wire [19:0] sources;
    wire [27:0] notes;
    wire [63:0] bends;
    wire [2:0] count;
    reg [3:0] ref_active = 0;
    integer ref_source [0:3], ref_note [0:3], ref_bend [0:3];
    reg [63:0] ref_age [0:3];
    reg [63:0] sequence_number = 0;
    reg [31:0] random_state = 32'h64739a12;
    integer checks = 0;

    // TIME_WIDTH=8 将旧版约86秒的回绕缩短到256拍，复现相同的排序错误。
    voice_allocator #(.VOICES(4), .IDX_WIDTH(2), .COUNT_WIDTH(3), .TIME_WIDTH(8)) dut (
        .clk(clk), .rst_n(rst_n), .event_valid(event_valid), .event_ready(event_ready),
        .event_type(event_type), .event_source_id(source), .event_note(note),
        .event_velocity(7'd100), .event_timbre(4'd0), .release_done(4'b1111),
        .cancel_valid(1'b0), .cancel_ready(), .cancel_mask(5'd0), .cancel_value(5'd0),
        .expr_valid(expr_valid), .expr_ready(expr_ready), .expr_source_id(expr_source),
        .expr_note(expr_note), .expr_pitch_bend(bend), .expr_aftertouch(8'd0),
        .expr_vibrato_depth(8'd0), .expr_vibrato_rate(8'd0),
        .voice_active(active), .voice_gate(gate), .voice_trigger(trigger),
        .voice_source_id_flat(sources), .voice_note_flat(notes), .voice_pitch_bend_flat(bends),
        .voice_count(count), .voice_velocity_flat(), .voice_timbre_flat(),
        .voice_aftertouch_flat(), .voice_vibrato_depth_flat(), .voice_vibrato_rate_flat(),
        .max_voice_count(), .note_on_count(), .note_off_count(), .steal_count(), .steal_pulse()
    );

    task check_state;
        integer i, expected_count;
        begin
            checks = checks + 1;
            expected_count = 0;
            if (active !== ref_active || gate !== ref_active)
                $fatal(1,"MODE %0d check %0d: active/gate=%b/%b expected=%b",MODE,checks,active,gate,ref_active);
            for (i=0; i<4; i=i+1) begin
                if (ref_active[i]) begin
                    expected_count = expected_count + 1;
                    if (sources[i*5+:5] !== ref_source[i][4:0] ||
                        notes[i*7+:7] !== ref_note[i][6:0] || bends[i*16+:16] !== ref_bend[i][15:0])
                        $fatal(1,"MODE %0d check %0d voice %0d: source/note/bend=%0d/%0d/%h expected=%0d/%0d/%h",
                            MODE,checks,i,sources[i*5+:5],notes[i*7+:7],bends[i*16+:16],ref_source[i],ref_note[i],ref_bend[i]);
                end
            end
            if (count !== expected_count[2:0]) $fatal(1,"voice count mismatch");
        end
    endtask

    task reset_case;
        integer i;
        begin
            @(negedge clk); rst_n=0; event_valid=0; expr_valid=0;
            ref_active=0; sequence_number=0;
            for(i=0;i<4;i=i+1) begin ref_source[i]=0; ref_note[i]=0; ref_bend[i]=0; ref_age[i]=0; end
            repeat(4) @(negedge clk);
            check_state();
            rst_n=1;
        end
    endtask

    task send_event(input bit on, input integer src, input integer n);
        integer i, same_source, same_note, free_slot, oldest, target;
        begin
            @(negedge clk); wait(event_ready);
            same_source=-1; same_note=-1; free_slot=-1; oldest=-1; target=-1;
            for(i=0;i<4;i=i+1) begin
                if(ref_active[i]) begin
                    if(ref_source[i]==src) same_source=i;
                    if(ref_note[i]==n) same_note=i;
                    if(oldest<0) oldest=i;
                    else if(ref_age[i]<ref_age[oldest]) oldest=i;
                    if(ref_source[i]==src && ref_note[i]==n) target=i;
                end else if(free_slot<0) free_slot=i;
            end
            if(on) begin
                target=(same_source>=0)?same_source:((same_note>=0)?same_note:((free_slot>=0)?free_slot:oldest));
                if(same_source<0) ref_bend[target]=0;
                ref_active[target]=1; ref_source[target]=src; ref_note[target]=n;
                sequence_number=sequence_number+1; ref_age[target]=sequence_number;
            end else if(target>=0) ref_active[target]=0;
            event_valid=1; event_type=on; source=src; note=n;
            @(negedge clk); event_valid=0;
            wait(event_ready); @(negedge clk);
            check_state();
        end
    endtask

    task send_expression(input integer src, input integer n, input integer value);
        integer i;
        begin
            @(negedge clk); wait(expr_ready);
            for(i=0;i<4;i=i+1)
                if(ref_active[i] && ref_source[i]==src) ref_bend[i]=value;
            expr_valid=1; expr_source=src; expr_note=n; bend=value;
            @(negedge clk); expr_valid=0;
            wait(expr_ready); @(negedge clk);
            check_state();
        end
    endtask

    integer n;
    initial begin
        reset_case();
        if(MODE==0) begin
            // 两个声部在回绕前分配，另两个在回绕后分配；第五音必须抢最早的声部。
            repeat(230) @(negedge clk);
            send_event(1,0,60); send_event(1,1,64);
            repeat(40) @(negedge clk);
            send_event(1,2,67); send_event(1,3,72); send_event(1,4,76);
            // 重触发更新先后顺序；释放留下空槽后仍须保持其余声部的相对先后。
            send_event(1,1,64); send_event(0,2,67); send_event(0,3,72);
            send_event(1,5,65); send_event(1,6,69); send_event(1,7,74);
            for(n=0;n<400;n=n+1) begin
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                repeat(random_state[7:0]) @(negedge clk);
                send_event(1,random_state[12:8]%16,48+random_state[19:15]);
            end
        end else if(MODE==1) begin
            send_event(1,0,60); send_event(1,1,60);
            send_event(0,0,60); // 旧来源的松键不能关闭已由来源1接管的同音。
            send_event(0,1,61); // 来源正确但音符过期，同样应忽略。
            send_event(0,1,60);
            send_event(1,2,64); send_event(1,2,67);
            send_event(0,2,64); send_event(0,2,67);
        end else if(MODE==2) begin
            send_event(1,0,60); send_event(1,1,60);
            send_expression(1,60,16'h1234);
            send_expression(0,60,16'h5678); // 旧来源不应按同音符兜底污染新来源。
            send_expression(1,0,16'h4321); // 合法表情继续按source_id匹配，note仅保留兼容字段。
        end else begin
            send_event(1,0,60); send_expression(0,60,16'h1234);
            send_event(1,0,60); // 同一来源重触发保留其表情。
            send_event(1,1,60); // 新来源接管同音时不能继承旧来源的弯音。
        end
        reset_case();
        send_event(1,0,60); send_event(0,0,60);
        done=1;
    end
    initial begin #5000000; $fatal(1,"allocator review timeout"); end
endmodule

module tb_allocator_age;
    wire done;
    allocator_review_case #(.MODE(0)) test_case(done);
    initial begin wait(done); $display("PASS tb_allocator_age: rollover, retrigger, free slots, 400 ordered allocations, reset"); $finish; end
endmodule
module tb_allocator_owner;
    wire done;
    allocator_review_case #(.MODE(1)) test_case(done);
    initial begin wait(done); $display("PASS tb_allocator_owner: stale note-off cannot stop a new owner, reset"); $finish; end
endmodule
module tb_allocator_expression_owner;
    wire done;
    allocator_review_case #(.MODE(2)) test_case(done);
    initial begin wait(done); $display("PASS tb_allocator_expression_owner: stale expression cannot change a new owner, reset"); $finish; end
endmodule
module tb_allocator_expression_reset;
    wire done;
    allocator_review_case #(.MODE(3)) test_case(done);
    initial begin wait(done); $display("PASS tb_allocator_expression_reset: new owner clears old expression, same source preserves it"); $finish; end
endmodule
