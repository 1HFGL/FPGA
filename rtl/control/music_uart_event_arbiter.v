// 两个事件生产者轮询，共用一个分配器。背压时锁住选择及对应队头。
// PC取消请求期间停止普通事件，等分配器IDLE与采样边界同时满足。
module music_uart_event_arbiter(
    input wire clk,rst_n,sample_request,
    input wire physical_valid,output wire physical_ready,
    input wire physical_preset,pc_preset,
    output wire event_preset,
    input wire physical_type,input wire [7:0] physical_source,
    input wire [6:0] physical_note,physical_velocity,
    input wire pc_valid,output wire pc_ready,input wire pc_type,
    input wire [6:0] pc_note,pc_velocity,
    input wire cancel_valid,output wire cancel_ready,
    output wire allocator_cancel,input wire allocator_cancel_ready,
    output wire event_valid,input wire event_ready,
    output wire event_type,output wire [7:0] event_source,
    output wire [6:0] event_note,event_velocity
);
    reg prefer_pc,locked,locked_pc;
    wire choose_pc=locked ? locked_pc : (pc_valid && (!physical_valid || prefer_pc));
    assign allocator_cancel=cancel_valid && sample_request && allocator_cancel_ready;
    assign cancel_ready=sample_request && allocator_cancel_ready;
    assign event_valid=!cancel_valid && (choose_pc ? pc_valid : physical_valid);
    assign event_preset=choose_pc ? pc_preset : physical_preset;
    assign event_type=choose_pc ? pc_type : physical_type;
    assign event_source=choose_pc ? {1'b1,pc_note} : physical_source;
    assign event_note=choose_pc ? pc_note : physical_note;
    assign event_velocity=choose_pc ? pc_velocity : physical_velocity;
    assign physical_ready=event_ready && event_valid && !choose_pc;
    assign pc_ready=event_ready && event_valid && choose_pc;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin prefer_pc<=0; locked<=0; locked_pc<=0; end
        else if(cancel_valid) locked<=0;
        else if(event_valid) begin
            if(event_ready) begin prefer_pc<=!choose_pc; locked<=0; end
            else begin locked<=1; locked_pc<=choose_pc; end
        end
    end
endmodule
