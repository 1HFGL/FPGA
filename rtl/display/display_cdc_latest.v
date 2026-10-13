// 跨时钟“单格信箱”：只搬运显示副本，绝不用于必须无损的音符事件。
// src_valid && src_ready 时接受一个完整数据字；忙时输入可丢弃，源端不能覆盖 hold_data。
// 目的端同步请求后才读稳定总线，并返回确认；不能把多位总线逐位同步后当原子数据。
// 两域复位必须共同异步断言、分别同步释放；不支持只复位一端。
module display_cdc_latest #(parameter integer WIDTH = 16) (
    input wire src_clk, src_rst_n,
    input wire src_valid,
    input wire [WIDTH-1:0] src_data,
    output wire src_ready,
    input wire dst_clk, dst_rst_n,
    output reg dst_valid,
    output reg [WIDTH-1:0] dst_data
);
    reg [WIDTH-1:0] hold_data;
    reg request_toggle, ack_toggle;
    reg ack_meta, ack_sync, req_meta, req_sync;
    assign src_ready = src_rst_n && (request_toggle == ack_sync);

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            ack_meta <= 1'b0;
            ack_sync <= 1'b0;
            hold_data <= {WIDTH{1'b0}};
            request_toggle <= 1'b0;
        end else begin
            ack_meta <= ack_toggle;
            ack_sync <= ack_meta;
            if (src_valid && src_ready) begin
                hold_data <= src_data;
                request_toggle <= ~request_toggle;
            end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            req_meta <= 1'b0;
            req_sync <= 1'b0;
            ack_toggle <= 1'b0;
            dst_valid <= 1'b0;
            dst_data <= {WIDTH{1'b0}};
        end else begin
            req_meta <= request_toggle;
            req_sync <= req_meta;
            dst_valid <= 1'b0;
            if (req_sync != ack_toggle) begin
                dst_data <= hold_data;
                dst_valid <= 1'b1;
                ack_toggle <= req_sync;
            end
        end
    end
endmodule
