// DVI 1.0图3-5的8位像素->10位TMDS编码；不是通用8b/10b编码。
// pixel_clk域，P0接受RGB/DE/控制位；P1输出对应字符。每拍吞吐一个像素。
// 两级流水：先减少相邻跳变，再按累计直流偏差决定是否反相。
// 消隐输出控制字符并将偏差归零；编码[0]最先发送。
module tmds_encoder(
    input wire pixel_clk,rst_n,
    input wire [7:0] data,
    input wire de,
    input wire [1:0] control,
    output reg [9:0] symbol
);
    reg [3:0] ones_data,ones_q;
    reg [8:0] q_comb;
    reg use_xnor;
    integer i;
    always @(*) begin
        ones_data=0;
        for(i=0;i<8;i=i+1) ones_data=ones_data+{3'b000,data[i]};
        use_xnor=(ones_data>4 || (ones_data==4 && !data[0]));
        q_comb[0]=data[0];
        for(i=1;i<8;i=i+1) q_comb[i]=q_comb[i-1]^data[i]^use_xnor;
        q_comb[8]=!use_xnor;
        ones_q=0;
        for(i=0;i<8;i=i+1) ones_q=ones_q+{3'b000,q_comb[i]};
    end
    reg [8:0] q;
    reg signed [5:0] balance,disparity;
    reg de_q;
    reg [1:0] control_q;
    always @(posedge pixel_clk or negedge rst_n) begin
        if(!rst_n) begin
            q<=0;balance<=0;disparity<=0;de_q<=0;control_q<=0;
            symbol<=10'b1101010100;
        end else begin
            q<=q_comb;
            balance<=$signed({1'b0,ones_q,1'b0})-6'sd8; // 2*N1-8，范围-8..8
            de_q<=de;control_q<=control;
            if(!de_q) begin
                disparity<=0;
                case(control_q)
                    2'b00:symbol<=10'b1101010100;
                    2'b01:symbol<=10'b0010101011;
                    2'b10:symbol<=10'b0101010100;
                    default:symbol<=10'b1010101011;
                endcase
            end else if(disparity==0 || balance==0) begin
                symbol<={~q[8],q[8],q[8] ? q[7:0] : ~q[7:0]};
                disparity<=q[8] ? disparity+balance : disparity-balance;
            end else if((!disparity[5] && !balance[5]) || (disparity[5] && balance[5])) begin
                symbol<={1'b1,q[8],~q[7:0]};
                disparity<=disparity-balance+(q[8] ? 6'sd2 : 6'sd0);
            end else begin
                symbol<={1'b0,q[8],q[7:0]};
                disparity<=disparity+balance-(q[8] ? 6'sd0 : 6'sd2);
            end
        end
    end
endmodule
