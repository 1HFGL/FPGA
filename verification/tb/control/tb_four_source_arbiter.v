`timescale 1ns/1ps
module tb_four_source_arbiter;
 reg clk=0,rst=0,accept=0,sample=0;
 reg pc_cancel=0,ble_cancel=0,touch_cancel=0;
 wire pr,cr,br,tr,cpr,cbr,ctr,av,at,ac,istouch;
 wire [8:0] source,mask,value;wire [6:0] note,vel;
 integer n,i,counts[0:3],cancels=0;
 reg [22:0] stalled_word;
 reg [2:0] last_cancel;
 always #10 clk=~clk;
 uart_event_arbiter #(.ENABLE_BLE(1),.ENABLE_TOUCH(1),.SOURCE_WIDTH(9)) dut(
  .clk(clk),.rst_n(rst),.sample_request(sample),
  .physical_valid(1'b1),.physical_ready(pr),.physical_type(1'b1),.physical_source(8'd0),.physical_note(7'd60),.physical_velocity(7'd96),
  .pc_valid(1'b1),.pc_ready(cr),.pc_type(1'b1),.pc_note(7'd60),.pc_velocity(7'd96),
  .ble_valid(1'b1),.ble_ready(br),.ble_type(1'b1),.ble_note(7'd60),.ble_velocity(7'd96),
  .touch_valid(1'b1),.touch_ready(tr),.touch_type(1'b1),.touch_source(8'h40),.touch_note(7'd60),.touch_velocity(7'd96),
  .cancel_valid(pc_cancel),.cancel_ready(cpr),.ble_cancel_valid(ble_cancel),.ble_cancel_ready(cbr),
  .touch_cancel_valid(touch_cancel),.touch_cancel_ready(ctr),.allocator_cancel(ac),.allocator_cancel_ready(1'b1),
  .allocator_cancel_mask(mask),.allocator_cancel_value(value),
  .event_valid(av),.event_ready(accept),.event_type(at),.event_source(source),.event_note(note),.event_velocity(vel),.event_touch(istouch));
 always @(posedge clk)if(rst)begin
  if(av && accept)begin
   case(source)
    9'h000:counts[0]=counts[0]+1;
    9'h13c:counts[1]=counts[1]+1;
    9'h1bc:counts[2]=counts[2]+1;
    9'h040:counts[3]=counts[3]+1;
    default:begin $display("FAIL four source encoding %h",source);$finish;end
   endcase
   if({tr,br,cr,pr}!=(source==0 ? 4'b0001 : source==9'h13c ? 4'b0010 : source==9'h1bc ? 4'b0100 : 4'b1000))begin
    $display("FAIL four source handshake");$finish;
   end
   if(istouch!=(source==9'h040))begin $display("FAIL touch timbre ownership");$finish;end
  end
  if(ac)begin
   last_cancel={ctr,cbr,cpr};
   if(!sample || av)begin $display("FAIL cancellation boundary");$finish;end
   if(ctr)begin
    if(mask!=9'h1f0 || value!=9'h040)begin $display("FAIL touch cancel mask");$finish;end
    for(i=0;i<512;i=i+1)if(((i&mask)==value)!=(i>=64 && i<80))begin $display("FAIL touch cancel isolation");$finish;end
   end else if(cpr)begin if(mask!=9'h180 || value!=9'h100)begin $display("FAIL PC mask");$finish;end end
   else if(cbr)begin if(mask!=9'h180 || value!=9'h180)begin $display("FAIL BLE mask");$finish;end end
   else begin $display("FAIL missing cancel ready");$finish;end
   cancels=cancels+1;
  end
 end
 initial begin
  for(n=0;n<4;n=n+1)counts[n]=0;
  repeat(4)@(negedge clk);rst=1;
  for(n=0;n<1000;n=n+1)begin
   accept=n%5!=0;@(negedge clk);
   if(!accept)begin
    stalled_word={source,note,vel};repeat(3)begin @(negedge clk);if({source,note,vel}!==stalled_word)begin $display("FAIL stalled event changed");$finish;end end
   end
  end
  accept=0;pc_cancel=1;ble_cancel=1;touch_cancel=1;
  repeat(3)begin
   repeat(5)@(negedge clk);sample=1;@(negedge clk);
   if(last_cancel[0])pc_cancel=0;else if(last_cancel[1])ble_cancel=0;else if(last_cancel[2])touch_cancel=0;
   sample=0;
  end
  for(n=0;n<4;n=n+1)if(counts[n]!=200)begin $display("FAIL four source fairness %d %d",n,counts[n]);$finish;end
  if(cancels!=3)begin $display("FAIL cancel arbitration");$finish;end
  rst=0;@(negedge clk);
  $display("PASS tb_four_source_arbiter: 800 events, equal four-source service, stable stalls, three cancellations, exhaustive touch mask isolation");$finish;
 end
endmodule
