module counter(
    input clk,
    input rst_n,
    input en,
    output reg [3:0] q
);

always@(posedge clk or negedge rst_n)
    if(!rst_n)begin
        q<=4'b0;
    end
    else if (en) begin
        if (q == 4'd15) begin
            q <= 4'd0;
        end
        else begin
            q <= q + 4'd1;
        end
    end

endmodule