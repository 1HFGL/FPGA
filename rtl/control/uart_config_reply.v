// 六个32位无符号数逐个转十进制，不并行展开六套除法。
// 整行XRESP由外层按换行仲裁；转换期间不能插入STATUS字符。
module uart_config_reply(
 input wire clk,rst_n,input wire request_valid,output wire request_ready,
 input wire [191:0] words,
 output wire tx_valid,input wire tx_ready,output wire [7:0] tx_data
);
 reg [2:0] state,field,pos;
 reg [191:0] pending;
 reg [31:0] binary;
 reg [39:0] bcd;
 reg [39:0] adjusted;
 reg [5:0] bit_count;
 reg [3:0] digit;
 reg started;
 integer i;
 wire skip=state==3 && !started && digit!=0 && bcd[digit*4+:4]==0;
 assign request_ready=state==0;
 assign tx_valid=state==1 || (state==3 && !skip) || state==4;
 reg [7:0] prefix;
 always @(*)begin
  case(pos)0:prefix="X";1:prefix="R";2:prefix="E";3:prefix="S";4:prefix="P";default:prefix=" ";endcase
  adjusted=bcd;
  for(i=0;i<10;i=i+1)if(bcd[i*4+:4]>=5)adjusted[i*4+:4]=bcd[i*4+:4]+4'd3;
 end
 assign tx_data=state==1?prefix:state==4?(field==5?8'd10:8'd32):8'd48+{4'd0,bcd[digit*4+:4]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;field<=0;pos<=0;pending<=0;binary<=0;bcd<=0;bit_count<=0;digit<=0;started<=0;end
  else case(state)
   0:if(request_valid)begin pending<=words;state<=1;pos<=0;field<=0;end
   1:if(tx_ready)begin
      if(pos==5)begin state<=2;binary<=pending[31:0];pending<=pending>>32;bcd<=0;bit_count<=0;end
      else pos<=pos+1'b1;
     end
   2:begin
      bcd<={adjusted[38:0],binary[31]};binary<=binary<<1;
      if(bit_count==31)begin state<=3;digit<=9;started<=0;end else bit_count<=bit_count+1'b1;
     end
   3:if(skip || tx_ready)begin
      if(!skip)started<=1;
      if(digit==0)state<=4;else digit<=digit-1'b1;
     end
   4:if(tx_ready)begin
      if(field==5)state<=0;
      else begin field<=field+1'b1;state<=2;binary<=pending[31:0];pending<=pending>>32;bcd<=0;bit_count<=0;end
     end
   default:state<=0;
  endcase
 end
endmodule
