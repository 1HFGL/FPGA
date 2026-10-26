`timescale 1ns/1ps
// A permanently drained byte FIFO accepts a byte even at full occupancy.
// Covers a deliberately filled FIFO, every occupancy, reset and flush recovery.
module tb_rx_drain_invariant;
 reg clk=0,rst_n=0,flush=0,iv=0,ready=0;
 reg [7:0] data=0;
 wire ir,ov;wire [7:0] out_data;wire [6:0] level;
 integer i,checks=0,seen_full=0;
 reg [31:0] random_state=32'hcb31d951;
 always #5 clk=~clk;
 uart_fifo #(.WIDTH(8),.ADDR_BITS(6)) dut(.clk(clk),.rst_n(rst_n),.flush(flush),
 .in_valid(iv),.in_ready(ir),.in_data(data),.out_valid(ov),.out_ready(ready),.out_data(out_data),.level(level));
 task check;
 begin
   #1;
   if(rst_n && !flush && ready && ir!==1'b1)begin $display("FAIL drain ready level=%0d",level);$stop;end
   if(rst_n && ready && iv && !ir && !flush)begin $display("FAIL unreachable receive overflow");$stop;end
   if(level==64)seen_full=seen_full+1;
   checks=checks+1;
 end
 endtask
 initial begin
   #1;rst_n=1;#1;rst_n=0;repeat(3)@(negedge clk);rst_n=1;
   iv=1;ready=0;
   repeat(64)begin @(negedge clk);data=data+1'b1;end
   ready=1;
   for(i=0;i<130;i=i+1)begin check;@(negedge clk);data=data+1'b1;end
   iv=0;
   repeat(66)begin check;@(negedge clk);end
   for(i=0;i<20000;i=i+1)begin
     random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
     iv=random_state[0];data=random_state[15:8];flush=random_state[7:1]==7'h7f;
     if(i%977==0)begin rst_n=0;iv=0;end else rst_n=1;
     check;@(negedge clk);
   end
   if(seen_full<64)begin $display("FAIL full exchange coverage");$stop;end
   $display("PASS tb_rx_drain_invariant: checks=%0d full_exchange=%0d",checks,seen_full);$finish;
 end
 initial begin #500000;$display("FAIL drain timeout");$stop;end
endmodule
