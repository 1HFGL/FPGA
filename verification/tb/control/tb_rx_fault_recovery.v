`timescale 1ns/1ps
module tb_rx_fault_recovery;
 parameter integer FAULT=0;
 reg clk=0,rst_n=0,rx=1,event_ready=0,cancel_ready=1;
 wire tx,event_valid,event_type,cancel_valid,session_ready,config_abort;
 wire [6:0] note,velocity;
 integer errors=0,aborts=0,events=0;
 always #10 clk=~clk;
 uart_synth_protocol #(.CLKS_PER_BIT(16),.WATCHDOG_CYCLES(500000),.ENABLE_CONFIG(1)) dut(
  .clk(clk),.rst_n(rst_n),.rx(rx),.tx(tx),.event_valid(event_valid),.event_ready(event_ready),
  .event_type(event_type),.event_note(note),.event_velocity(velocity),
  .cancel_valid(cancel_valid),.cancel_ready(cancel_ready),.voice_count(6'd0),.max_voice_count(6'd0),
  .steal_count(32'd0),.session_ready(session_ready),.config_valid(),.config_ready(1'b1),
  .config_kind(),.config_seq(),.config_arg1(),.config_arg2(),.config_abort(config_abort),
  .config_reply_valid(1'b0),.config_reply_ready(),.config_reply_words(192'd0));
 always @(posedge clk)if(rst_n)begin
   if(dut.rx_bad)errors=errors+1;
   if(config_abort)aborts=aborts+1;
   if(event_valid && event_ready)events=events+1;
   if(dut.rx_valid && !dut.rx_ready && !dut.rx_flush)begin $display("FAIL receive overflow invariant");$stop;end
 end
 task byte_send;
 input [7:0] b;input bad;
 integer i;
 begin
   @(negedge clk);rx=0;repeat(16)@(negedge clk);
   for(i=0;i<8;i=i+1)begin rx=b[i];repeat(16)@(negedge clk);end
   rx=!bad;repeat(16)@(negedge clk);rx=1;repeat(16)@(negedge clk);
 end
 endtask
 task send;
 input [255:0] text;
 integer i;
 begin for(i=31;i>=0;i=i-1)if(text[i*8+:8]!=0)byte_send(text[i*8+:8],0);end
 endtask
 initial begin
   #1;rst_n=1;#1;rst_n=0;repeat(8)@(negedge clk);rst_n=1;
   send("HELLO\n");repeat(8)@(negedge clk);
   if(!session_ready)begin $display("FAIL RX recovery handshake");$stop;end
   send("NOTE_ON 60 100 0\n");repeat(8)@(negedge clk);
   if(!event_valid || note!=60)begin $display("FAIL RX recovery initial queue");$stop;end
   errors=0;aborts=0;cancel_ready=0;
   if(FAULT)force dut.rx_fault=1'b0;
   byte_send(8'h55,1);repeat(64)@(negedge clk);
   if(errors!=1 || aborts<1 || !cancel_valid || event_valid)begin
     $display("FAIL framing fault did not flush/cancel err=%0d abort=%0d cancel=%b event=%b",errors,aborts,cancel_valid,event_valid);$stop;
   end
   cancel_ready=1;event_ready=1;repeat(8)@(negedge clk);
   send("\n");send("NOTE_ON 64 99 0\n");repeat(8)@(negedge clk);
   if(events!=1)begin $display("FAIL framing recovery/stale queue events=%0d",events);$stop;end
   // Asynchronous reset while a byte is in flight must suppress stale data.
   @(negedge clk);rx=0;repeat(40)@(negedge clk);#3;rst_n=0;#1;
   if(dut.rx_valid!==0 || event_valid!==0)begin $display("FAIL RX asynchronous reset");$stop;end
   rx=1;repeat(8)@(negedge clk);rst_n=1;
   send("HELLO\n");send("NOTE_OFF 64 0\n");repeat(8)@(negedge clk);
   if(events!=2 || !session_ready)begin $display("FAIL RX restart events=%0d",events);$stop;end
   $display("PASS tb_rx_fault_recovery: real bad stop bit, flush/cancel, no stale event, reset mid-byte and restart");$finish;
 end
 initial begin #4000000;$display("FAIL RX recovery timeout");$stop;end
endmodule
