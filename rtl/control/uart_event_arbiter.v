// 实体/PC/可选BLE事件轮询；仅在已解码事件层仲裁，不拼接UART字节。
// 背压锁住队头；取消在采样边界、分配器IDLE时应用，只释放对应来源。
// 旧配置保持8位来源；BLE配置使用9位：实体00xxxxxxx、PC10nnnnnnn、BLE11nnnnnnn。
module uart_event_arbiter #(
    parameter integer ENABLE_BLE=0,
    parameter integer SOURCE_WIDTH=ENABLE_BLE ? 9 : 8
)(
    input wire clk,rst_n,sample_request,
    input wire physical_valid,output wire physical_ready,
    input wire physical_type,input wire [7:0] physical_source,
    input wire [6:0] physical_note,physical_velocity,
    input wire pc_valid,output wire pc_ready,input wire pc_type,
    input wire [6:0] pc_note,pc_velocity,
    input wire cancel_valid,output wire cancel_ready,
    output wire allocator_cancel,input wire allocator_cancel_ready,
    output wire event_valid,input wire event_ready,
    output wire event_type,output wire [SOURCE_WIDTH-1:0] event_source,
    output wire [6:0] event_note,event_velocity,
    input wire ble_valid,output wire ble_ready,input wire ble_type,
    input wire [6:0] ble_note,ble_velocity,
    input wire ble_cancel_valid,output wire ble_cancel_ready,
    output wire [SOURCE_WIDTH-1:0] allocator_cancel_mask,allocator_cancel_value
);
    reg [1:0] next_source,locked_source;
    reg locked,prefer_ble_cancel;
    reg [1:0] selected;
    wire bv=ENABLE_BLE && ble_valid;
    wire bc=ENABLE_BLE && ble_cancel_valid;
    wire cancelling=cancel_valid || bc;
    wire cancel_ble=bc && (!cancel_valid || prefer_ble_cancel);
    always @(*)begin
        selected=0;
        if(locked)selected=locked_source;
        else case(next_source)
            0: if(physical_valid)selected=0;else if(pc_valid)selected=1;else if(bv)selected=2;
            1: if(pc_valid)selected=1;else if(bv)selected=2;else selected=0;
            default: if(bv)selected=2;else if(physical_valid)selected=0;else if(pc_valid)selected=1;
        endcase
    end
    assign allocator_cancel=cancelling && sample_request && allocator_cancel_ready;
    assign cancel_ready=sample_request && allocator_cancel_ready && !cancel_ble;
    assign ble_cancel_ready=ENABLE_BLE && sample_request && allocator_cancel_ready && cancel_ble;
    assign allocator_cancel_mask=ENABLE_BLE ? 9'h180 : 8'h80;
    assign allocator_cancel_value=cancel_ble ? 9'h180 : (ENABLE_BLE ? 9'h100 : 8'h80);
    assign event_valid=!cancelling && ((selected==2) ? bv : (selected==1) ? pc_valid : physical_valid);
    assign event_type=(selected==2) ? ble_type : (selected==1) ? pc_type : physical_type;
    assign event_source=(selected==2) ? {2'b11,ble_note} : (selected==1) ?
        (ENABLE_BLE ? {2'b10,pc_note} : {1'b1,pc_note}) : physical_source;
    assign event_note=(selected==2) ? ble_note : (selected==1) ? pc_note : physical_note;
    assign event_velocity=(selected==2) ? ble_velocity : (selected==1) ? pc_velocity : physical_velocity;
    assign physical_ready=event_ready && event_valid && selected==0;
    assign pc_ready=event_ready && event_valid && selected==1;
    assign ble_ready=ENABLE_BLE && event_ready && event_valid && selected==2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin next_source<=0;locked<=0;locked_source<=0;prefer_ble_cancel<=0;end
        else if(cancelling) begin
            locked<=0;
            if(allocator_cancel)prefer_ble_cancel<=!cancel_ble;
        end
        else if(event_valid) begin
            if(event_ready) begin
                next_source<=(selected==0)?2'd1:(selected==1 && ENABLE_BLE)?2'd2:2'd0;
                locked<=0;
            end else begin locked<=1;locked_source<=selected;end
        end
    end
endmodule
