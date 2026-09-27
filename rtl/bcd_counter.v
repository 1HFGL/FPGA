module bcd_counter (
    clk,
    cin,
    rst_n,
    cout,
    q
);
    input clk;
    input cin;
    input rst_n;

    output reg cout;
    output [3:0] q;

    reg [3:0] cnt;

    always @(posedge clk or negedge rst_n)
        if (rst_n == 1'b0) 
        cnt <= 4'b0;
        else if (cin == 1'b1) begin
            if (cnt == 4'd9) 
            cnt <= 4'b0;
            else 
            cnt <= cnt + 4'b1;
        end 
        else 
        cnt <= cnt;

    always @(posedge clk or negedge rst_n)
        if (rst_n == 1'b0) 
        cout <= 1'b0;
        else if (cin == 1'b1 && cnt == 4'd9) 
        cout <= 1'b1;
        else 
        cout <= 1'b0;

    assign q = cnt;



endmodule
