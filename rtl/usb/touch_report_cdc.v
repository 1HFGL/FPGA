// Single outstanding report. USB polls only when src_ready; the payload remains
// stable until destination acceptance has crossed back. Disconnect resets the
// entire mailbox in both domains and cancels held notes through connected.
module touch_report_cdc(
    input wire src_clk,src_rst_n,src_valid,
    input wire [415:0] src_data,
    output wire src_ready,
    input wire dst_clk,dst_rst_n,dst_ready,
    output reg dst_valid,
    output reg [415:0] dst_data
);
    reg request,acknowledge;
    reg ack_meta,ack_sync,req_meta,req_sync;
    reg [415:0] hold_data;
    assign src_ready=src_rst_n && request==ack_sync;
    always @(posedge src_clk or negedge src_rst_n)begin
        if(!src_rst_n)begin request<=0;ack_meta<=0;ack_sync<=0;hold_data<=0;end
        else begin
            ack_meta<=acknowledge;ack_sync<=ack_meta;
            if(src_valid && src_ready)begin hold_data<=src_data;request<=!request;end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n)begin
        if(!dst_rst_n)begin req_meta<=0;req_sync<=0;acknowledge<=0;dst_valid<=0;dst_data<=0;end
        else begin
            req_meta<=request;req_sync<=req_meta;
            if(!dst_valid && req_sync!=acknowledge)begin dst_data<=hold_data;dst_valid<=1;end
            else if(dst_valid && dst_ready)begin acknowledge<=req_sync;dst_valid<=0;end
        end
    end
endmodule
