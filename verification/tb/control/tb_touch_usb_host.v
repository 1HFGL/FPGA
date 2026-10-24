`timescale 1ns/1ps
// Independent transaction-level device model. Line/CRC testing is separate.
module tb_touch_usb_host #(parameter integer FAULT=0);
 reg clk=0,rst=0,tick=0,ready_report=1;
 reg [1:0] line=1;
 always #10 clk=~clk;
 integer clock_ms=0,cycles=0;
 always @(posedge clk)begin
  cycles=cycles+1;tick<=clock_ms==199;
  if(clock_ms==199)clock_ms<=0;else clock_ms<=clock_ms+1;
 end
 wire reset_bus,enable,connected,valid,cv,ct;
 wire [415:0] report;
 wire [7:0] cp,debug;
 wire [6:0] ca,cl;
 wire [3:0] ce;
 wire [63:0] cb;
 reg done=0,error=0;
 reg [7:0] response=0;
 reg [15:0] count=0;
 reg [511:0] payload=0;
 reg pending=0;
 wire cr=!pending;
 integer delay_count=0,offset=0,wanted=0,request=0,value=0,dev_addr=0;
 integer i,n,received=0,polls=0,enumerations=0,errors_sent=0,naks=0;
 integer bus_resets=0;
 reg was_connected=0;
 always @(posedge reset_bus)bus_resets=bus_resets+1;
 always @(posedge clk)if(connected)was_connected<=1;
 reg direction=0,data_toggle=1,poll_toggle=0,configured=0;
 reg inject_crc=1,inject_nak=1,inject_duplicate=1,inject_short=0;
 reg [7:0] saved_pid;
 reg [3:0] saved_ep;
 reg [6:0] saved_length;
 reg saved_toggle;
 reg [63:0] saved_setup;
 reg [7:0] device_desc[0:17],config_desc[0:33];
 touch_usb_host #(.CLOCKS_PER_MS(200),.ATTACH_MS(2),.RESET_MS(2),.RECOVERY_MS(2)) dut(
  .clk(clk),.rst_n(rst),.line_state(line),.host_transmitting(1'b0),.bus_reset(reset_bus),.link_enable(enable),
  .connected(connected),.report_valid(valid),.report_ready(ready_report),.report_data(report),.debug_state(debug),
  .command_valid(cv),.command_ready(cr),.command_pid(cp),.command_address(ca),.command_endpoint(ce),
  .command_toggle(ct),.command_length(cl),.command_payload(cb),.link_frame_tick(tick),
  .transaction_done(done),.transaction_error(error),.response(response),.received_length(count),.received_payload(payload));
 always @(posedge clk)begin
  done<=0;
  if(!rst || reset_bus)begin dev_addr=0;configured=0;poll_toggle=0;pending<=0;end
  else begin
   if(valid && ready_report)begin
    if(report[7:0]!=1 || !connected)begin $display("FAIL report identity/connection");$finish;end
    received=received+1;
   end
   if(cv && cr)begin
    if(ca!=dev_addr)begin $display("FAIL device address got=%0d expected=%0d",ca,dev_addr);$finish;end
    saved_pid=cp;saved_ep=ce;saved_length=cl;saved_toggle=ct;saved_setup=cb;
    pending<=1;delay_count=4;
   end else if(pending)begin
    if(delay_count!=0)delay_count=delay_count-1;
    else begin
     pending<=0;done<=1;error<=0;response<=8'hd2;count<=0;payload<=0;
     if(saved_pid==8'h2d)begin
      if(saved_length!=8 || saved_toggle!=0)begin $display("FAIL setup packet");$finish;end
      request=saved_setup[15:8];value=saved_setup[31:16];wanted=saved_setup[63:48];
      direction=saved_setup[7];offset=0;data_toggle=1;
      if(FAULT==5 && request==9)response<=8'h1e;
     end else if(saved_pid==8'he1)begin
      if(!direction || saved_length!=0 || saved_toggle!=1)begin $display("FAIL control read status");$finish;end
     end else if(saved_ep==0)begin
      if(direction && wanted>offset)begin
       if(FAULT==6)begin response<=8'h5a;naks=naks+1;end
       else if(FAULT==7)begin error<=1;response<=0;errors_sent=errors_sent+1;end
       else if(inject_nak)begin response<=8'h5a;inject_nak=0;naks=naks+1;end
       else if(inject_crc)begin error<=1;response<=8'h4b;inject_crc=0;errors_sent=errors_sent+1;end
       else if(inject_duplicate && offset>0)begin
        response<=data_toggle?8'hc3:8'h4b;inject_duplicate=0;count<=64;
       end else begin
        n=(wanted-offset>64)?64:wanted-offset;
        if(request==6 && value==16'h0100 && n>18-offset)n=18-offset;
        if(request==6 && value==16'h0200 && n>34-offset)n=34-offset;
        if(request==6 && value==16'h2200 && n>455-offset)n=455-offset;
        response<=data_toggle?8'h4b:8'hc3;count<=n;
        for(i=0;i<64;i=i+1)if(i<n)begin
         if(request==6 && value==16'h0100)payload[i*8+:8]<=device_desc[offset+i];
         else if(request==6 && value==16'h0200)payload[i*8+:8]<=config_desc[offset+i];
         else if(request==1)payload[i*8+:8]<=i==0?8'd2:FAULT==4?8'd5:8'd6;
         else payload[i*8+:8]<=offset+i;
        end
        offset=offset+n;data_toggle=!data_toggle;
       end
      end else begin
       response<=8'h4b;
       if(request==5)dev_addr=value;
       if(request==9)begin configured=1;poll_toggle=0;enumerations=enumerations+1;end
       if(request==10)response<=8'h1e; // optional SET_IDLE unsupported
      end
     end else begin
      if(!configured || saved_ep!=2)begin $display("FAIL wrong interrupt endpoint");$finish;end
      polls=polls+1;
      if(FAULT==8)begin error<=1;response<=0;errors_sent=errors_sent+1;end
      else if(FAULT==9)response<=8'h1e;
      else if(polls%3==0)begin response<=8'h5a;naks=naks+1;end
      else begin
       response<=poll_toggle?8'h4b:8'hc3;poll_toggle=!poll_toggle;
       count<=inject_short?51:52;payload[7:0]<=1;payload[15:8]<=1;
       payload[39:24]<=1024;payload[55:40]<=2048;payload[415:408]<=1;
      end
     end
    end
   end
  end
 end
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
  if(FAULT==1)device_desc[8]=8'h87;
  if(FAULT==2)config_desc[27]=0;
  if(FAULT==3)config_desc[30]=2;
  repeat(5)@(negedge clk);rst=1;
  if(FAULT!=0)begin
   wait(bus_resets>=2);repeat(5)@(negedge clk);
   if(connected || received!=0 || (FAULT<=7 && was_connected) || (FAULT>=8 && !was_connected))begin
    $display("FAIL invalid host condition accepted fault=%d",FAULT);$finish;
   end
   if(FAULT==6 && naks<100)begin $display("FAIL NAK deadline coverage");$finish;end
   if(FAULT==8 && errors_sent!=9)begin $display("FAIL poll error budget %d",errors_sent);$finish;end
   $display("PASS tb_touch_usb_host: rejected fault=%0d; bounded re-enumeration, no report publication",FAULT);$finish;
  end else begin
  wait(received>=8);@(negedge clk);ready_report=0;
  repeat(400)@(negedge clk);n=polls;repeat(1000)@(negedge clk);
  if(polls!=n)begin $display("FAIL report backpressure polling");$finish;end
  ready_report=1;inject_short=1;wait(!connected);inject_short=0;
  wait(enumerations>=2 && received>=12);line=0;repeat(1000)@(negedge clk);
  if(connected || errors_sent!=1 || naks==0 || inject_duplicate)begin $display("FAIL recovery coverage");$finish;end
  line=1;wait(enumerations>=3 && connected);rst=0;repeat(3)@(negedge clk);
  if(connected || valid)begin $display("FAIL reset");$finish;end
  $display("PASS tb_touch_usb_host: EP0 multi-packet, address, config parsing, NAK/CRC/duplicate retries, SET_IDLE STALL, short packet recovery, backpressure, detach/re-enumeration/reset reports=%0d",received);$finish;
  end
 end
 initial begin #5000000;$display("FAIL USB host timeout state=%h reports=%0d",debug,received);$finish;end
endmodule
