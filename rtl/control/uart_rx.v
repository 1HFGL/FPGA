// 8N1接收器：仅使用clk，不把位计数器输出当时钟。
// valid/frame_error为一拍脉冲；只有停止位为1才提交data。
module uart_rx #(parameter integer CLKS_PER_BIT=434)(
    input wire clk,rst_n,rx,
    output reg [7:0] data,
    output reg valid,frame_error
);
    // 异步串口只进入meta；meta -> sync_q必须保留正常时序分析。
    reg rx_meta,rx_sync,rx_previous;
    reg [15:0] timer;
    reg [2:0] bit_index;
    reg [7:0] shift;
    reg [1:0] state;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rx_meta<=1; rx_sync<=1; rx_previous<=1; end
        else begin rx_meta<=rx; rx_sync<=rx_meta; rx_previous<=rx_sync; end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            timer<=0; bit_index<=0; shift<=0; data<=0;
            valid<=0; frame_error<=0; state<=0;
        end else begin
            valid<=0; frame_error<=0;
            case(state)
                0: if(rx_previous && !rx_sync) begin
                    timer<=CLKS_PER_BIT/2-1; state<=1;
                end
                1: if(timer!=0) timer<=timer-1'b1;
                   else if(!rx_sync) begin timer<=CLKS_PER_BIT-1; bit_index<=0; state<=2; end
                   else state<=0;
                2: if(timer!=0) timer<=timer-1'b1;
                   else begin
                       shift[bit_index]<=rx_sync; timer<=CLKS_PER_BIT-1;
                       if(bit_index==7) state<=3; else bit_index<=bit_index+1'b1;
                   end
                3: if(timer!=0) timer<=timer-1'b1;
                   else begin
                       if(rx_sync) begin data<=shift; valid<=1; end
                       else frame_error<=1;
                       state<=0;
                   end
                default: state<=0;
            endcase
        end
    end
endmodule
