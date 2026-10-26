`timescale 1ns/1ps
// Full port test: independent USB device at D+/D-, without transaction injection.
module tb_usb_dual_wire;
 reg sys_clk=0,pll_rst_n=0,rst=0,attached=1,drive=0,dp_out=1,dm_out=0,accept=1;
 wire clk,pin_clk,locked;
 always #10 sys_clk=~sys_clk;
 initial begin #100;pll_rst_n=1;end
 GSR GSR(.GSRI(1'b1));
 usb_clock_60k clocks(.sys_clk(sys_clk),.rst_n(pll_rst_n),.usb_clk(clk),.usb_pin_clk(pin_clk),.locked(locked));
 tri dp,dm;
 pulldown (weak0) (dp);pulldown (weak0) (dm);
 assign (pull1,highz0) dp=attached?1'b1:1'bz;
 assign dp=drive?dp_out:1'bz;
 assign dm=drive?dm_out:1'bz;
 wire connected,valid;wire [415:0] report;wire [7:0] debug;
 touch_usb_port #(.SEPARATE_PIN_CLOCK(1)) dut(.clk(clk),.pin_clk(pin_clk),.rst_n(rst),.usb_dp(dp),.usb_dm(dm),
  .connected(connected),.report_valid(valid),.report_ready(accept),.report_data(report),
  .debug_state(debug),.debug_line(),.debug_detail());
 // Shorten attachment delays only. Actual 48MHz PHY, 1ms SOF and retries remain.
 defparam dut.u_host.ATTACH_MS=2;
 defparam dut.u_host.RESET_MS=2;
 defparam dut.u_host.RECOVERY_MS=2;
 wire oe=dut.oe;
 reg [7:0] rxbytes[0:79],bytes[0:79],device_desc[0:17],config_desc[0:33];
 integer rxlen,ones,last_line,bit_no,bit_value,samples,tx_ones,tx_line;
 reg [7:0] decoded;
 integer i,j,size,request,value,wanted,offset=0,dev_addr=0;
 integer sof_count=0,setups=0,reports=0,sent=0,enumerations=0;
 integer crc_errors=0,duplicates=0,naks=0;
 reg direction=0,data_toggle=1,poll_toggle=0,configured=0;
 reg [63:0] setup;
 reg [15:0] checksum;
 reg [10:0] token,previous_sof=0;
 reg [415:0] expected_report;
 always @(posedge dut.bus_reset)begin
  dev_addr=0;configured=0;poll_toggle=0;previous_sof=0;offset=0;
 end
 always @(posedge clk)if(valid && accept)begin
  if(report!==expected_report || !connected)begin $display("FAIL whole wire report %d",reports);$finish;end
  reports=reports+1;
 end
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

 task check_data;
  input [7:0] wanted_pid;input integer wanted_size;
  integer k;reg [15:0] c;
  begin
   if(rxlen!=wanted_size+4 || rxbytes[1]!=wanted_pid)begin $display("FAIL wire data size/PID");$finish;end
   c=16'hffff;for(k=0;k<wanted_size;k=k+1)c=crc16(c,rxbytes[k+2]);
   if({rxbytes[rxlen-1],rxbytes[rxlen-2]}!==~c)begin $display("FAIL wire host CRC16");$finish;end
  end
 endtask
 task receive_ack;
  begin receive;if(rxlen!=2 || rxbytes[1]!=8'hd2)begin $display("FAIL expected ACK");$finish;end end
 endtask
 initial begin
  for(i=0;i<18;i=i+1)device_desc[i]=0;
  device_desc[0]=18;device_desc[1]=1;device_desc[2]=0;device_desc[3]=2;device_desc[7]=64;
  device_desc[8]=8'h86;device_desc[9]=8'h1a;device_desc[10]=8'he3;device_desc[11]=8'he5;device_desc[17]=1;
  for(i=0;i<34;i=i+1)config_desc[i]=0;
  config_desc[0]=9;config_desc[1]=2;config_desc[2]=34;config_desc[4]=1;config_desc[5]=1;
  config_desc[9]=9;config_desc[10]=4;config_desc[13]=1;config_desc[14]=3;
  config_desc[18]=9;config_desc[19]=8'h21;config_desc[23]=1;config_desc[24]=8'h22;
  config_desc[25]=8'hc7;config_desc[26]=1;
  config_desc[27]=7;config_desc[28]=5;config_desc[29]=8'h82;config_desc[30]=3;config_desc[31]=64;config_desc[33]=1;
  expected_report=0;expected_report[7:0]=1;expected_report[415:408]=6;
  for(i=0;i<6;i=i+1)begin
   expected_report[(1+8*i)*8+:8]=1;expected_report[(2+8*i)*8+:8]=i+10;
   expected_report[(3+8*i)*8+:16]=300+i*500;expected_report[(5+8*i)*8+:16]=3000;
  end
  wait(locked);repeat(8)@(negedge clk);rst=1;
  forever begin
   receive;
   token={rxbytes[3][2:0],rxbytes[2]};
   if(rxbytes[1]==8'ha5)begin
    check_token(8'ha5,token);
    if(token!=previous_sof+1)begin $display("FAIL SOF sequence");$finish;end
    previous_sof=token;sof_count=sof_count+1;
   end else begin
    if(token[6:0]!=dev_addr)begin $display("FAIL wire address %d/%d",token[6:0],dev_addr);$finish;end
    check_token(rxbytes[1],token);
    if(rxbytes[1]==8'h2d)begin
     if(token[10:7]!=0)begin $display("FAIL setup endpoint");$finish;end
     receive;check_data(8'hc3,8);
     for(j=0;j<8;j=j+1)setup[j*8+:8]=rxbytes[j+2];
     request=setup[15:8];value=setup[31:16];wanted=setup[63:48];direction=setup[7];
     offset=0;data_toggle=1;setups=setups+1;send_packet(8'hd2,0,0,0);
    end else if(rxbytes[1]==8'he1)begin
     if(token[10:7]!=0 || !direction)begin $display("FAIL OUT status token");$finish;end
     receive;check_data(8'h4b,0);send_packet(8'hd2,0,0,0);
    end else if(rxbytes[1]==8'h69 && token[10:7]==0)begin
     if(direction && offset<wanted)begin
      size=(wanted-offset>64)?64:wanted-offset;
      for(j=0;j<size;j=j+1)begin
       if(request==6 && value==16'h0100)bytes[j]=device_desc[offset+j];
       else if(request==6 && value==16'h0200)bytes[j]=config_desc[offset+j];
       else if(request==1)bytes[j]=j==0?2:6;
       else bytes[j]=(offset+j)&255;
      end
      send_packet(data_toggle?8'h4b:8'hc3,size,0,0);receive_ack;
      offset=offset+size;data_toggle=!data_toggle;
     end else if(request==10)send_packet(8'h1e,0,0,0);
     else begin
      send_packet(8'h4b,0,0,0);receive_ack;
      if(request==5)dev_addr=value;
      if(request==9)begin configured=1;enumerations=enumerations+1;end
     end
    end else if(rxbytes[1]==8'h69 && token[10:7]==2 && configured)begin
     for(j=0;j<52;j=j+1)bytes[j]=expected_report[j*8+:8];
     if(naks==0 || sent>=4)begin send_packet(8'h5a,0,0,0);naks=naks+1;end
     else if(crc_errors==0)begin send_packet(poll_toggle?8'h4b:8'hc3,52,1,0);crc_errors=1;end
     else if(sent==1 && duplicates==0)begin
      send_packet(poll_toggle?8'hc3:8'h4b,52,0,0);receive_ack;duplicates=1;
     end else begin
      send_packet(poll_toggle?8'h4b:8'hc3,52,0,0);receive_ack;
      sent=sent+1;poll_toggle=!poll_toggle;
     end
    end else begin $display("FAIL unexpected wire token %h ep%0d",rxbytes[1],token[10:7]);$finish;end
   end
  end
 end
 initial begin
  wait(reports==2);@(negedge clk);accept=0;
  repeat(150000)@(negedge clk);
  if(reports!=2)begin $display("FAIL stalled consumer report loss");$finish;end
  accept=1;wait(reports==4);repeat(1000)@(negedge clk);attached=0;
  repeat(200000)@(negedge clk);
  if(connected || valid || crc_errors!=1 || duplicates!=1 || sof_count<6 || setups!=9)begin
   $display("FAIL wire detach/coverage conn%b reports%d setup%d",connected,reports,setups);$finish;
  end
  sent=0;attached=1;wait(reports>=6);repeat(1000)@(negedge clk);
  if(enumerations!=2 || !connected)begin $display("FAIL wire reconnect");$finish;end
  rst=0;repeat(8)@(negedge clk);
  if(connected || valid || !oe)begin $display("FAIL wire reset release");$finish;end
  $display("PASS tb_usb_dual_wire: full D+/D- enumeration/455-byte EP0, SOF, address/config, SET_IDLE STALL, NAK, bad CRC, duplicate ACK, six whole six-contact reports, backpressure, detach/reconnect/reset");$finish;
 end
 initial begin #60000000;$display("FAIL wire timeout state=%h reports%d setups%d",debug,reports,setups);$finish;end
endmodule
