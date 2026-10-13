// 单时钟、2的幂深度FIFO。flush丢弃全部旧事务，优先于同拍进出队。
// 未ready时队头保持；满队列可同拍出队/入队，空队列无旁路。
module uart_fifo #(parameter integer WIDTH=8, parameter integer ADDR_BITS=4)(
    input wire clk,rst_n,flush,
    input wire in_valid,output wire in_ready,input wire [WIDTH-1:0] in_data,
    output wire out_valid,input wire out_ready,output wire [WIDTH-1:0] out_data,
    output wire [ADDR_BITS:0] level
);
    localparam integer DEPTH=1<<ADDR_BITS;
    reg [WIDTH-1:0] mem[0:DEPTH-1];
    reg [ADDR_BITS-1:0] rd,wr;
    reg [ADDR_BITS:0] count;
    wire pop=out_valid && out_ready;
    wire push=in_valid && in_ready;
    assign out_valid=rst_n && !flush && count!=0;
    assign in_ready=rst_n && !flush && (count<DEPTH || pop);
    assign out_data=mem[rd];
    assign level=count;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rd<=0; wr<=0; count<=0; end
        else if(flush) begin rd<=0; wr<=0; count<=0; end
        else begin
            if(push) begin mem[wr]<=in_data; wr<=wr+1'b1; end
            if(pop) rd<=rd+1'b1;
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: count<=count;
            endcase
        end
    end
endmodule
