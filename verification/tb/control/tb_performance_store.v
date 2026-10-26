`timescale 1ns/1ps
module tb_performance_store;
 reg clk=0,rst=0,abort=0,valid=0,rr=0,remote_ready=1,gc=1,mc=1;
 reg [3:0] kind=0;reg [31:0] seq=0,a=0,b=0;reg [8:0] index=0;
 wire ready,rv,remote_valid,dv,dc;wire [191:0] result;wire [3:0] rk;wire [7:0] rval,bpm;
 wire [9:0] count;wire [36:0] mask;wire [15:0] duration;wire [103:0] keymap;wire [31:0] sid,mid;
 reg [31:0] song[0:1025],mapping[0:13];reg [191:0] last;
 integer i,controls=0,commits=0;
 always #5 clk=~clk;
 performance_store #(.TIMEOUT_CYCLES(5000)) dut(.clk(clk),.rst_n(rst),.abort_upload(abort),
 .request_valid(valid),.request_ready(ready),.request_kind(kind),.seq(seq),.arg1(a),.arg2(b),
 .reply_valid(rv),.reply_ready(rr),.reply_words(result),.remote_valid(remote_valid),.remote_ready(remote_ready),
 .remote_kind(rk),.remote_value(rval),.guide_can_commit(gc),.map_can_commit(mc),.actual_flags(32'd0),.guide_progress(10'd9),
 .download_valid(dv),.download_committed(dc),.download_count(count),.download_bpm(bpm),
 .read_index(index),.read_mask(mask),.read_duration(duration),.keymap(keymap),.song_identity(sid),.map_identity(mid));
 always @(posedge clk)begin if(remote_valid && remote_ready)controls=controls+1;if(dc)commits=commits+1;end
 task request;input [3:0] k;input [31:0] id,x,y,code;
 begin
  @(negedge clk);while(!ready)@(negedge clk);kind=k;seq=id;a=x;b=y;valid=1;
  @(negedge clk);valid=0;while(!rv)@(negedge clk);last=result;
  if(result[31:0]!=id || result[63:32]!=code)begin $display("FAIL command %d seq=%d code=%d expected=%d",k,id,result[63:32],code);$finish;end
  rr=1;@(negedge clk);rr=0;
 end endtask
 task sample;input integer n;
 begin index=n;repeat(3)@(negedge clk);
  if(mask!=={song[3+2*n][4:0],song[2+2*n]} || duration!==song[3+2*n][20:5])begin $display("FAIL score read index=%d mask=%h duration=%d",n,mask,duration);$finish;end
 end endtask
 initial begin
  $readmemh("verification/data/control_score.hex",song);$readmemh("verification/data/control_mapping.hex",mapping);
  repeat(5)@(negedge clk);rst=1;
  for(i=0;i<13;i=i+1)if(keymap[i*8+:8]!=i)begin $display("FAIL default mapping");$finish;end
  request(7,1,1,1026,0);
  request(8,1,1,90,4);request(8,1,0,32'hffffffff,2);
  for(i=0;i<1026;i=i+1)begin
    request(8,1,i,song[i],0);
    if(last[95:64]!=i+1)begin $display("FAIL ACK next index");$finish;end
    if(i%37==0)request(8,1,i,song[i],0);
  end
  request(8,1,4,song[4],0);request(8,1,5,song[5],0);request(8,1,5,song[5]^1,4);
  request(9,1,32'hdeadbeef,0,5);gc=0;request(9,1,32'h62fc80d2,0,3);
  if(dv)begin $display("FAIL bad commit changed active score");$finish;end
  gc=1;request(9,1,32'h62fc80d2,0,0);request(9,1,32'h62fc80d2,0,0);
  if(!dv || count!=512 || sid!=32'h62fc80d2 || commits!=1)begin $display("FAIL score commit identity/count");$finish;end
  for(i=0;i<512;i=i+1)sample(i);
  request(7,2,1,4,0);request(8,2,0,32'h4a5a0001,0);request(8,2,1,100,0);request(8,2,2,32'h76543210,0);
  sample(0);sample(511);request(8,2,3,0,2);request(10,2,0,0,0);if(commits!=1)begin $display("FAIL invalid upload swapped bank");$finish;end
  request(7,3,2,14,0);for(i=0;i<14;i=i+1)request(8,3,i,mapping[i],0);
  request(8,3,4,mapping[4],0);mc=0;request(9,3,32'h3fb771fa,0,3);
  if(keymap[7:0]!=0)begin $display("FAIL half mapping visible");$finish;end
  mc=1;request(9,3,32'h3fb771fa,0,0);if(mid!=32'h3fb771fa || keymap[103:96]!=255 || keymap[7:0]!=12)begin $display("FAIL map commit");$finish;end
  request(11,90,3,0,0);request(11,90,3,0,0);request(11,90,3,1,4);
  if(controls!=1)begin $display("FAIL duplicate CTRL applied twice");$finish;end
  request(12,91,0,0,0);if(last[127:96]!=32'h62fc80d2 || last[159:128]!=32'h3fb771fa)begin $display("FAIL GETCFG identity");$finish;end
  request(7,4,1,4,0);repeat(5100)@(negedge clk);request(8,4,0,32'h4a5a0001,6);
  request(7,5,1,4,0);abort=1;repeat(3)@(negedge clk);abort=0;request(9,5,0,0,6);
  if(!dv || sid!=32'h62fc80d2 || mid!=32'h3fb771fa)begin $display("FAIL disconnect lost active config");$finish;end
  $display("PASS tb_performance_store: 512 segments, independent CRC, duplicates/order/bounds, RAM banks, BUSY, atomic map, CTRL retry, query, timeout/disconnect");$finish;
 end
 initial begin #2000000;$display("FAIL store timeout");$finish;end
endmodule
