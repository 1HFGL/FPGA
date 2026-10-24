`timescale 1ns/1ps
// Independent NRZI/bit-stuff/CRC device model, connected at physical D+/D-.
module tb_touch_usb_link;
 reg clk=0,rst=0,enabled=0,cv=0,toggle=0;
 always #10.416 clk=~clk;
 reg [7:0] pid=0;reg [6:0] address=0,length=0;reg [3:0] endpoint=0;
 reg [63:0] tx=0;
 wire cr,done,error,tick,txvalid,txready,rv,ra,re,oe,hp,hn;
 wire [7:0] response,td,rd;wire [15:0] count;wire [511:0] payload;wire [1:0] ls;
 reg drive=0,dp_out=1,dm_out=0;
 tri dp,dm;pullup(dp);pulldown(dm);
 assign dp=drive?dp_out:(!oe?hp:1'bz);
 assign dm=drive?dm_out:(!oe?hn:1'bz);
 touch_usb_link dut(.clk(clk),.rst_n(rst),.enabled(enabled),.command_valid(cv),.command_ready(cr),
  .command_pid(pid),.command_address(address),.command_endpoint(endpoint),.command_toggle(toggle),
  .command_length(length),.command_payload(tx),.done(done),.error(error),.response(response),
  .received_length(count),.received_payload(payload),.frame_tick(tick),
  .utmi_rx_data(rd),.utmi_rxvalid(rv),.utmi_rxactive(ra),.utmi_rxerror(re),.utmi_txready(txready),
  .utmi_linestate(ls),.utmi_tx_data(td),.utmi_txvalid(txvalid));
 usb_fs_phy phy(.clk_i(clk),.rstn_i(rst),.utmi_data_out_i(td),.utmi_txvalid_i(txvalid),
  .utmi_op_mode_i(2'd0),.utmi_xcvrselect_i(2'd1),.utmi_termselect_i(1'b0),
  .utmi_dppulldown_i(1'b1),.utmi_dmpulldown_i(1'b1),
  .usb_rx_rcv_i(dp && !dm),.usb_rx_dp_i(dp),.usb_rx_dn_i(dm),.usb_reset_assert_i(1'b0),
  .utmi_data_in_o(rd),.utmi_txready_o(txready),.utmi_rxvalid_o(rv),.utmi_rxactive_o(ra),
  .utmi_rxerror_o(re),.utmi_linestate_o(ls),.usb_tx_dp_o(hp),.usb_tx_dn_o(hn),.usb_tx_oen_o(oe),
  .usb_reset_detect_o(),.usb_en_o());
 reg [7:0] rxbytes[0:79],bytes[0:79];
 integer rxlen,ones,last_line,bit_no,byte_no,bit_value,samples,n,j,tests=0;
 integer tx_ones,tx_line;
 reg [7:0] decoded;
 reg [15:0] checksum;
 reg phy_error_seen=0;
 always @(posedge clk)if(re)phy_error_seen<=1;
 function [15:0] crc16;
  input [15:0] old;input [7:0] data;
  reg [15:0] c;integer i;
  begin c=old;for(i=0;i<8;i=i+1)begin if(c[0]^data[i])c=(c>>1)^16'ha001;else c=c>>1;end crc16=c;end
 endfunction
 function [4:0] crc5;
  input [10:0] data;reg [4:0] c;integer i;
  begin c=31;for(i=0;i<11;i=i+1)begin if(c[0]^data[i])c=(c>>1)^5'h14;else c=c>>1;end crc5=~c;end
 endfunction
 task receive;
  begin
   wait(!oe && dp==0 && dm==1);
   repeat(2)@(posedge clk);#1;
   rxlen=0;ones=0;last_line=1;bit_no=0;decoded=0;samples=0;
   while(!(dp==0 && dm==0) && samples<700)begin
    if(dp===dm)begin $display("FAIL host SE1/unknown");$finish;end
    bit_value=(dp==last_line);last_line=dp;
    if(ones==6)begin
     if(bit_value!=0)begin $display("FAIL host bit stuffing");$finish;end
     ones=0;
    end else begin
     decoded[bit_no]=bit_value;
     ones=bit_value?ones+1:0;
     if(bit_no==7)begin
      if(rxlen==0 && decoded!=8'h80)begin $display("FAIL host SYNC %h",decoded);$finish;end
      rxbytes[rxlen]=decoded;rxlen=rxlen+1;bit_no=0;
     end else bit_no=bit_no+1;
    end
    repeat(4)@(posedge clk);#1;samples=samples+1;
   end
   if(samples==700 || bit_no!=0)begin $display("FAIL host packet framing");$finish;end
   wait(oe);@(negedge clk);
  end
 endtask
 task check_token;
  input [7:0] wanted_pid;input [10:0] token;
  reg [15:0] expected;
  begin expected={crc5(token),token};
   if(rxlen!=4 || rxbytes[1]!=wanted_pid || {rxbytes[3],rxbytes[2]}!==expected)begin
    $display("FAIL host token got %h %h %h expected %h %h",rxbytes[1],rxbytes[3],rxbytes[2],wanted_pid,expected);$finish;
   end
  end
 endtask
 task device_bit;
  input value;input skip_stuff;
  begin
   if(!value)tx_line=!tx_line;
   dp_out=tx_line;dm_out=!tx_line;repeat(4)@(negedge clk);
   tx_ones=value?tx_ones+1:0;
   if(tx_ones==6 && !skip_stuff)begin
    tx_line=!tx_line;dp_out=tx_line;dm_out=!tx_line;repeat(4)@(negedge clk);tx_ones=0;
   end
  end
 endtask
 task device_byte;
  input [7:0] value;input skip_stuff;integer b;
  begin for(b=0;b<8;b=b+1)device_bit(value[b],skip_stuff);end
 endtask
 task send_packet;
  input [7:0] response_pid;input integer size;input corrupt_crc,stuff_error;
  integer i;reg [15:0] c;
  begin
   repeat(8)@(negedge clk);drive=1;tx_line=1;tx_ones=0;
   device_byte(8'h80,0);device_byte(response_pid,0);c=16'hffff;
   if(response_pid==8'hc3 || response_pid==8'h4b)begin
    for(i=0;i<size;i=i+1)begin device_byte(bytes[i],stuff_error);c=crc16(c,bytes[i]);end
    c=~c;if(corrupt_crc)c=c^1;
    device_byte(c[7:0],0);device_byte(c[15:8],0);
   end
   dp_out=0;dm_out=0;repeat(8)@(negedge clk);
   dp_out=1;dm_out=0;repeat(4)@(negedge clk);drive=0;
  end
 endtask
 task launch;
  input [7:0] token_pid;input [6:0] addr;input [3:0] ep;input integer size;input dt;
  begin
   @(negedge clk);pid=token_pid;address=addr;endpoint=ep;length=size;toggle=dt;cv=1;
   while(!cr)@(negedge clk);
   @(negedge clk);cv=0;
  end
 endtask
 initial begin
  for(n=0;n<80;n=n+1)bytes[n]=(n%4==0)?255:n;
  repeat(8)@(negedge clk);rst=1;enabled=1;
  tx=64'h00ff7f800001ffff;
  fork
   begin launch(8'h2d,7'h25,0,8,0);wait(done);if(error || response!=8'hd2)begin $display("FAIL setup result");$finish;end end
   begin receive;check_token(8'h2d,11'h025);receive;
    if(rxlen!=12 || rxbytes[1]!=8'hc3)begin $display("FAIL setup data length");$finish;end
    checksum=16'hffff;for(j=0;j<8;j=j+1)begin
     if(rxbytes[j+2]!==tx[j*8+:8])begin $display("FAIL setup payload");$finish;end
     checksum=crc16(checksum,rxbytes[j+2]);
    end
    if({rxbytes[11],rxbytes[10]}!==~checksum)begin $display("FAIL host data CRC");$finish;end
    send_packet(8'hd2,0,0,0);
   end
  join
  tests=tests+1;
  fork
   begin launch(8'h69,1,2,0,0);wait(done);
    if(error || response!=8'hc3 || count!=52)begin $display("FAIL input result err=%b pid=%h len=%d",error,response,count);$finish;end
    for(j=0;j<52;j=j+1)if(payload[j*8+:8]!==bytes[j])begin $display("FAIL input byte %0d",j);$finish;end
   end
   begin receive;check_token(8'h69,11'h101);send_packet(8'hc3,52,0,0);receive;
    if(rxlen!=2 || rxbytes[1]!=8'hd2)begin $display("FAIL host ACK");$finish;end
   end
  join
  tests=tests+1;
  fork
   begin launch(8'h69,1,2,0,1);wait(done);if(!error)begin $display("FAIL CRC not rejected");$finish;end end
   begin receive;send_packet(8'h4b,52,1,0);end
  join
  repeat(100)begin @(negedge clk);if(!oe)begin $display("FAIL ACKed corrupt CRC");$finish;end end
  tests=tests+1;
  phy_error_seen=0;
  fork
   begin launch(8'h69,1,2,0,1);wait(done);if(!error || !phy_error_seen)begin $display("FAIL stuffing not rejected");$finish;end end
   begin receive;send_packet(8'h4b,4,0,1);end
  join
  repeat(100)begin @(negedge clk);if(!oe)begin $display("FAIL ACKed malformed PHY");$finish;end end
  tests=tests+1;
  fork
   begin launch(8'h69,1,2,0,1);wait(done);if(!error)begin $display("FAIL overlength not rejected");$finish;end end
   begin receive;send_packet(8'h4b,65,0,0);end
  join
  repeat(100)begin @(negedge clk);if(!oe)begin $display("FAIL ACKed overlength packet");$finish;end end
  tests=tests+1;
  fork begin launch(8'h69,1,2,0,0);wait(done);if(error || response!=8'h5a)begin $display("FAIL NAK");$finish;end end
       begin receive;send_packet(8'h5a,0,0,0);end join
  tests=tests+1;
  fork begin launch(8'h69,1,2,0,0);wait(done);if(error || response!=8'h1e)begin $display("FAIL STALL");$finish;end end
       begin receive;send_packet(8'h1e,0,0,0);end join
  tests=tests+1;
  fork begin launch(8'h69,1,2,0,0);wait(done);if(!error)begin $display("FAIL no response timeout");$finish;end end
       begin receive;end join
  tests=tests+1;
  receive;check_token(8'ha5,1);receive;check_token(8'ha5,2);
  $display("PASS tb_touch_usb_link: %0d physical D+/D- transactions, token/data CRC, stuffing, valid52/ACK, corrupt CRC no ACK, malformed PHY, NAK/STALL/timeout, SOF increment",tests);$finish;
 end
 initial begin #5000000;$display("FAIL physical USB timeout tests=%d",tests);$finish;end
endmodule
