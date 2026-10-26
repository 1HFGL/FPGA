`timescale 1ns/1ps
// 从C的2026-10-14事件队列适配：每键4项暂存+共享FIFO，按键轮转服务。
// 上升沿event_valid&&event_ready出队；背压保持队头，溢出锁存至复位。
// octave只在首次按下时取值；旧音松键沿用当时音高，防止切档后卡音。
module event_encoder #(
    parameter integer KEY_COUNT=2, NOTE_BASE=60, MAX_EVENTS=64, PTR_WIDTH=6, SOURCE_WIDTH=5,
    parameter integer CHROMATIC_KEYS=0, ENABLE_PLAY_CONTROL=0, ENABLE_KEYMAP=0
) (
    input wire clk, rst_n,
    input wire [KEY_COUNT-1:0] key_press, key_release,
    input wire [KEY_COUNT*7-1:0] key_velocity_flat,
    input wire [3:0] input_timbre,
    input wire [1:0] octave_select, // 0低档、1中档、2高档；仅ENABLE_PLAY_CONTROL启用
    output reg input_overflow,
    output wire event_valid, event_type,
    output wire [SOURCE_WIDTH-1:0] event_source_id,
    output wire [6:0] event_note, event_velocity,
    output wire [3:0] event_timbre,
    input wire event_ready,
    input wire [103:0] keymap,output wire mapping_idle
);
    localparam integer EVENT_WIDTH=SOURCE_WIDTH+19;
    localparam integer KEY_PTR_WIDTH=(KEY_COUNT>1)?$clog2(KEY_COUNT):1;
    reg [18:0] pending_mem [0:KEY_COUNT*4-1];
    reg [1:0] pending_wr [0:KEY_COUNT-1], pending_rd [0:KEY_COUNT-1];
    reg [2:0] pending_count [0:KEY_COUNT-1];
    reg held_valid [0:KEY_COUNT-1];
    reg [6:0] held_note [0:KEY_COUNT-1];
    reg [KEY_PTR_WIDTH-1:0] rr_key;
    reg [EVENT_WIDTH-1:0] fifo_mem [0:MAX_EVENTS-1];
    reg [PTR_WIDTH-1:0] wr_ptr, rd_ptr;
    reg [PTR_WIDTH:0] fifo_count;
    integer i, scan, selected, first_any, first_after;
    reg found_any, found_after;
    reg found;
    reg [SOURCE_WIDTH-1:0] selected_source;
    assign mapping_idle=!input_overflow && !found_any && fifo_count==0 && !(|key_press) && !(|key_release);
    wire do_read=event_valid && event_ready;
    wire do_write=found && !input_overflow && ((fifo_count<MAX_EVENTS) || do_read);
    wire [EVENT_WIDTH-1:0] rd_data=fifo_mem[rd_ptr];
    assign event_valid=!input_overflow && fifo_count!=0;
    assign event_type=rd_data[SOURCE_WIDTH+18];
    assign event_source_id=rd_data[SOURCE_WIDTH+17:18];
    assign event_note=rd_data[17:11];
    assign event_velocity=rd_data[10:4];
    assign event_timbre=rd_data[3:0];
    function [6:0] key_to_note;
        input integer key_index;
        input [1:0] octave;
        integer value,offset;
        begin
            offset=ENABLE_KEYMAP?keymap[key_index*8+:8]:key_index;
            case(ENABLE_PLAY_CONTROL ? octave : 2'd1)
                2'd0: value=NOTE_BASE-12+offset;
                2'd2: value=NOTE_BASE+12+offset;
                default: value=NOTE_BASE+offset;
            endcase
            // 默认二键仍为C/E，13键采用半音排列；保持旧工程接口兼容。
            if(!CHROMATIC_KEYS) begin
                case(key_index)
                    1: value=value+3;
                    2: value=value+5;
                    3: value=value+9;
                    default: value=value;
                endcase
            end
            if(value<0) key_to_note=0;
            else if(value>127) key_to_note=127;
            else key_to_note=value[6:0];
        end
    endfunction
    // Two constant-index priority selections implement the same round-robin
    // order without thirteen variable-index pending_count multiplexers.
    always @* begin
        found_any=0; found_after=0; first_any=0; first_after=0;
        for(scan=KEY_COUNT-1;scan>=0;scan=scan-1) begin
            if(pending_count[scan]!=0) begin
                found_any=1; first_any=scan;
                if(scan>=rr_key) begin found_after=1; first_after=scan; end
            end
        end
        found=found_any;
        selected=found_after?first_after:first_any;
        selected_source=selected[SOURCE_WIDTH-1:0];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr<=0; rd_ptr<=0; fifo_count<=0; rr_key<=0; input_overflow<=0;
            for(i=0;i<KEY_COUNT;i=i+1) begin
                pending_wr[i]<=0; pending_rd[i]<=0; pending_count[i]<=0;
                held_valid[i]<=0; held_note[i]<=0;
            end
        end else if(input_overflow) begin
            // 故障后停止事件投递；上层只清理实体键来源，不误关PC或未来触摸。
            fifo_count<=0;
            for(i=0;i<KEY_COUNT;i=i+1) begin pending_count[i]<=0; held_valid[i]<=0; end
        end else begin
            for(i=0;i<KEY_COUNT;i=i+1) begin
                if(key_press[i] && key_release[i]) input_overflow<=1;
                if((key_press[i] && (!ENABLE_KEYMAP || keymap[i*8+:8]!=255 || held_valid[i])) || (key_release[i] && held_valid[i])) begin
                    if(pending_count[i]<4 || (do_write && selected==i)) begin
                        if(key_press[i]) begin
                            pending_mem[i*4+pending_wr[i]]<={1'b1,
                                held_valid[i]?held_note[i]:key_to_note(i,octave_select),
                                key_velocity_flat[i*7+:7],input_timbre};
                            if(!held_valid[i]) held_note[i]<=key_to_note(i,octave_select);
                            held_valid[i]<=1;
                        end else begin
                            // 切八度后松键，仍然送出原先按下的音高。
                            pending_mem[i*4+pending_wr[i]]<={1'b0,held_note[i],7'd0,input_timbre};
                            held_valid[i]<=0;
                        end
                        pending_wr[i]<=pending_wr[i]+1'b1;
                        if(!(do_write && selected==i)) pending_count[i]<=pending_count[i]+1'b1;
                    end else input_overflow<=1;
                end else if(do_write && selected==i) pending_count[i]<=pending_count[i]-1'b1;
                if(do_write && selected==i) pending_rd[i]<=pending_rd[i]+1'b1;
            end
            if(do_write) begin
                fifo_mem[wr_ptr]<={pending_mem[selected*4+pending_rd[selected]][18],selected_source,
                                  pending_mem[selected*4+pending_rd[selected]][17:0]};
                wr_ptr<=wr_ptr+1'b1;
                if(selected==KEY_COUNT-1) rr_key<=0;
                else rr_key<=selected[KEY_PTR_WIDTH-1:0]+1'b1;
            end
            if(do_read) rd_ptr<=rd_ptr+1'b1;
            case({do_write,do_read})
                2'b10: fifo_count<=fifo_count+1'b1;
                2'b01: fifo_count<=fifo_count-1'b1;
                default: fifo_count<=fifo_count;
            endcase
        end
    end
endmodule
