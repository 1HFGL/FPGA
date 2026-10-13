// valid && ready沿锁存字节，低位先发。忙时上游保存数据；复位TX高。
module uart_tx #(parameter integer CLKS_PER_BIT=434)(
    input wire clk,rst_n,
    input wire [7:0] data,input wire valid,
    output wire ready,output wire tx
);
    reg busy;
    reg [9:0] shift;
    reg [15:0] timer;
    reg [3:0] bit_index;
    assign ready=rst_n && !busy;
    assign tx=busy ? shift[0] : 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin busy<=0; shift<=10'h3ff; timer<=0; bit_index<=0; end
        else if(!busy) begin
            if(valid) begin
                shift<={1'b1,data,1'b0}; timer<=CLKS_PER_BIT-1; bit_index<=0; busy<=1;
            end
        end else if(timer!=0) timer<=timer-1'b1;
        else if(bit_index==9) busy<=0;
        else begin
            shift<={1'b1,shift[9:1]}; bit_index<=bit_index+1'b1; timer<=CLKS_PER_BIT-1;
        end
    end
endmodule
