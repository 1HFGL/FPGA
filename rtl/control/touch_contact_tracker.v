// 已解码触点快照 -> 有所有权的音符/控件事件（50MHz单时钟域）。
// USB/HID适配器须先校验完整报告，并将坐标转成1024x600像素。
// frame_valid&&frame_ready接受整张快照；等待期间上游保持数据。
// 5点快照最多产生10条音符事件，逐条握手；不会静默丢弃松键。
// source=0x40..0x44按内部槽分配，与报告数组顺序无关。
// 断连/坏报告先排空已提出的事件，再握手cancel(掩码f0/值40)。
// 此模块尚不是USB主机，正式顶层只有获得设备/电气证据后才能接入。
module touch_contact_tracker #(
    parameter integer CONTACTS=5,
    parameter [6:0] VELOCITY=7'd96
)(
    input wire clk,rst_n,connected,stream_error,
    input wire frame_valid,
    output wire frame_ready,
    input wire [CONTACTS-1:0] contact_active,
    input wire [CONTACTS*8-1:0] contact_id,
    input wire [CONTACTS*12-1:0] contact_x,contact_y,
    input wire instrument_guitar,
    input wire [1:0] octave,
    output wire event_valid,
    input wire event_ready,
    output reg event_on,
    output reg [7:0] event_source,
    output reg [6:0] event_note,
    output wire [6:0] event_velocity,
    output reg event_guitar,
    output wire control_valid,
    input wire control_ready,
    output reg [1:0] control_kind,control_value,
    output wire cancel_valid,
    input wire cancel_ready,
    output wire [7:0] cancel_mask,cancel_value,
    output reg fault
);
    localparam [3:0] OFFLINE=0,IDLE=1,CHECK=2,OLD=3,NEW=4,SEND=5,REON=6,CONTROL=7,CANCEL=8;
    reg [3:0] state,resume_state;
    reg [3:0] index;
    reg abort_pending;
    reg [CONTACTS-1:0] active_q,occupied,held,blocked,frozen,mode_mem;
    reg [CONTACTS*8-1:0] id_q,id_mem;
    reg [CONTACTS*12-1:0] x_q,y_q;
    reg [CONTACTS*7-1:0] note_mem;
    reg [CONTACTS*4-1:0] key_mem;
    reg mode_q;
    reg [6:0] base_note;
    reg match_found,exists,free_found,duplicate;
    reg [3:0] match_index,free_index;
    reg [11:0] map_x,map_y;
    wire map_note,map_black;
    wire [3:0] map_index;
    wire [1:0] map_control,map_value;
    wire [6:0] target_note=base_note+{3'd0,map_index};
    // 7bit音符槽地址 = 槽号*7。明确写成移位减法，避免综合成乘法DSP。
    wire [6:0] note_offset={index,3'b000}-{3'd0,index};
    wire [6:0] free_note_offset={free_index,3'b000}-{3'd0,free_index};
    // 同一槽号只解码一次；固定切片按独热掩码汇总，避免每个字段各自做动态移位。
    // 仍为组合读取，不增加快照处理、事件或取消的拍数。
    wire [CONTACTS-1:0] index_select;
    genvar slot;
    generate for(slot=0;slot<CONTACTS;slot=slot+1)begin:g_index
        assign index_select[slot]=(index==slot);
    end endgenerate
    reg index_occupied,index_active,index_held,index_blocked,index_frozen,index_mode;
    reg [7:0] index_old_id,index_new_id;
    reg [6:0] index_note;
    reg [3:0] index_key;
    reg [11:0] index_x,index_y;
    integer selected_slot;
    always @(*)begin
        index_occupied=0;index_active=0;index_held=0;index_blocked=0;index_frozen=0;index_mode=0;
        index_old_id=0;index_new_id=0;index_note=0;index_key=0;index_x=0;index_y=0;
        for(selected_slot=0;selected_slot<CONTACTS;selected_slot=selected_slot+1)begin
            index_occupied=index_occupied | (index_select[selected_slot] & occupied[selected_slot]);
            index_active=index_active | (index_select[selected_slot] & active_q[selected_slot]);
            index_held=index_held | (index_select[selected_slot] & held[selected_slot]);
            index_blocked=index_blocked | (index_select[selected_slot] & blocked[selected_slot]);
            index_frozen=index_frozen | (index_select[selected_slot] & frozen[selected_slot]);
            index_mode=index_mode | (index_select[selected_slot] & mode_mem[selected_slot]);
            index_old_id=index_old_id | ({8{index_select[selected_slot]}} & id_mem[selected_slot*8+:8]);
            index_new_id=index_new_id | ({8{index_select[selected_slot]}} & id_q[selected_slot*8+:8]);
            index_note=index_note | ({7{index_select[selected_slot]}} & note_mem[selected_slot*7+:7]);
            index_key=index_key | ({4{index_select[selected_slot]}} & key_mem[selected_slot*4+:4]);
            index_x=index_x | ({12{index_select[selected_slot]}} & x_q[selected_slot*12+:12]);
            index_y=index_y | ({12{index_select[selected_slot]}} & y_q[selected_slot*12+:12]);
        end
    end
    integer k,j;
    assign frame_ready=state==IDLE && connected && !stream_error && !abort_pending;
    assign event_valid=state==SEND;
    assign control_valid=state==CONTROL;
    assign cancel_valid=state==CANCEL;
    assign cancel_mask=8'hf0;
    assign cancel_value=8'h40;
    assign event_velocity=VELOCITY;
    instrument_ui_map u_hit(.x(map_x),.y(map_y),.instrument_guitar(mode_q),
        .note_valid(map_note),.key_black(map_black),.note_index(map_index),
        .key_left(),.key_right(),.key_top(),.key_bottom(),
        .control_kind(map_control),.control_value(map_value));

    always @(*)begin
        match_found=0;match_index=0;exists=0;free_found=0;free_index=0;duplicate=0;
        map_x=12'hfff;map_y=12'hfff;
        for(k=0;k<CONTACTS;k=k+1)begin
            if(index<CONTACTS && index_occupied && active_q[k] &&
               index_old_id==id_q[k*8+:8])begin match_found=1;match_index=k;end
            if(index<CONTACTS && occupied[k] && id_mem[k*8+:8]==index_new_id)exists=1;
            if(!occupied[k] && !free_found)begin free_found=1;free_index=k;end
            for(j=k+1;j<CONTACTS;j=j+1)
                if(active_q[k] && active_q[j] && id_q[k*8+:8]==id_q[j*8+:8])duplicate=1;
        end
        if((state==OLD || state==REON) && match_found)begin
            map_x=x_q[match_index*12+:12];map_y=y_q[match_index*12+:12];
        end else if(state==NEW && index<CONTACTS)begin
            map_x=index_x;map_y=index_y;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=OFFLINE;resume_state<=IDLE;index<=0;abort_pending<=0;
            active_q<=0;occupied<=0;held<=0;blocked<=0;frozen<=0;mode_mem<=0;
            id_q<=0;id_mem<=0;x_q<=0;y_q<=0;note_mem<=0;key_mem<=0;mode_q<=0;base_note<=60;
            event_on<=0;event_source<=0;event_note<=0;event_guitar<=0;
            control_kind<=0;control_value<=0;fault<=0;
        end else begin
            if((!connected || stream_error) && state!=OFFLINE)abort_pending<=1;
            if(stream_error)fault<=1;
            if(abort_pending && state!=SEND && state!=CONTROL && state!=CANCEL && state!=OFFLINE)
                state<=CANCEL;
            else case(state)
                OFFLINE:if(connected && !stream_error)begin state<=IDLE;abort_pending<=0;end
                IDLE:if(frame_valid && frame_ready)begin
                    active_q<=contact_active;id_q<=contact_id;x_q<=contact_x;y_q<=contact_y;
                    mode_q<=instrument_guitar;
                    base_note<=octave==0?7'd48:octave==2?7'd72:7'd60;
                    state<=CHECK;index<=0;
                end
                CHECK:begin
                    if(duplicate)begin state<=CANCEL;fault<=1;end
                    else state<=OLD;
                end
                OLD:begin
                    if(index==CONTACTS)begin index<=0;state<=NEW;end
                    else if(!index_occupied)index<=index+1'b1;
                    else if(!match_found)begin
                        occupied[index]<=0;held[index]<=0;
                        if(index_held)begin
                            event_on<=0;event_source<=8'h40+{4'd0,index};
                            event_note<=index_note;event_guitar<=index_mode;
                            state<=SEND;resume_state<=OLD;
                        end
                        index<=index+1'b1;
                    end else if(index_blocked || index_frozen || index_mode!=mode_q)begin
                        if(index_mode!=mode_q)frozen[index]<=1;
                        index<=index+1'b1;
                    end else if(index_held && (!map_note || index_key!=map_index))begin
                        event_on<=0;event_source<=8'h40+{4'd0,index};
                        event_note<=index_note;event_guitar<=index_mode;
                        held[index]<=0;state<=SEND;resume_state<=REON;
                    end else if(!index_held && map_note)begin
                        held[index]<=1;note_mem[note_offset+:7]<=target_note;key_mem[index*4+:4]<=map_index;
                        event_on<=1;event_source<=8'h40+{4'd0,index};
                        event_note<=target_note;event_guitar<=mode_q;
                        state<=SEND;resume_state<=OLD;index<=index+1'b1;
                    end else index<=index+1'b1;
                end
                REON:begin
                    if(map_note)begin
                        held[index]<=1;note_mem[note_offset+:7]<=target_note;key_mem[index*4+:4]<=map_index;
                        event_on<=1;event_source<=8'h40+{4'd0,index};event_note<=target_note;
                        event_guitar<=mode_q;state<=SEND;resume_state<=OLD;
                    end else state<=OLD;
                    index<=index+1'b1;
                end
                NEW:begin
                    if(index==CONTACTS)state<=IDLE;
                    else if(!index_active || exists)index<=index+1'b1;
                    else if(!free_found)begin state<=CANCEL;fault<=1;end
                    else begin
                        occupied[free_index]<=1;id_mem[free_index*8+:8]<=index_new_id;
                        mode_mem[free_index]<=mode_q;frozen[free_index]<=0;
                        blocked[free_index]<=map_control!=0;held[free_index]<=map_note;
                        note_mem[free_note_offset+:7]<=target_note;
                        key_mem[free_index*4+:4]<=map_index;
                        if(map_note)begin
                            event_on<=1;event_source<=8'h40+{4'd0,free_index};
                            event_note<=target_note;event_guitar<=mode_q;
                            state<=SEND;resume_state<=NEW;
                        end else if(map_control!=0)begin
                            control_kind<=map_control;control_value<=map_value;state<=CONTROL;
                        end
                        index<=index+1'b1;
                    end
                end
                SEND:if(event_ready)state<=abort_pending?CANCEL:resume_state;
                CONTROL:if(control_ready)state<=abort_pending?CANCEL:NEW;
                CANCEL:if(cancel_ready)begin
                    occupied<=0;held<=0;blocked<=0;frozen<=0;active_q<=0;index<=0;
                    abort_pending<=0;state<=connected && !stream_error?IDLE:OFFLINE;
                end
                default:begin state<=CANCEL;fault<=1;end
            endcase
        end
    end
endmodule
