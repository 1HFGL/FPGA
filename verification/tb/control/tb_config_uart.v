`timescale 1ns/1ps
module tb_config_uart;
 reg clk=0,rst=0,rx=1;wire tx;always #5 clk=~clk;
 wire req,ready,abort,rep,repready,rv,remote;wire [3:0] kind,rkind;wire [7:0] rvalue;
 wire [31:0] seq,a,b;wire [191:0] words;wire [7:0] byte_out;wire bad;
 wire dv,dc;wire [31:0] identity;
 uart_synth_protocol #(.CLKS_PER_BIT(16),.VOICES(32),.ENABLE_GUITAR(1),.ENABLE_CONFIG(1),.WATCHDOG_CYCLES(2000000)) protocol(
 .clk(clk),.rst_n(rst),.rx(rx),.tx(tx),.event_ready(1'b1),.cancel_ready(1'b1),.voice_count(6'd0),.max_voice_count(6'd32),.steal_count(32'd0),
 .config_valid(req),.config_ready(ready),.config_kind(kind),.config_seq(seq),.config_arg1(a),.config_arg2(b),.config_abort(abort),
 .config_reply_valid(rep),.config_reply_ready(repready),.config_reply_words(words));
 performance_store store(.clk(clk),.rst_n(rst),.abort_upload(abort),.request_valid(req),.request_ready(ready),.request_kind(kind),
 .seq(seq),.arg1(a),.arg2(b),.reply_valid(rep),.reply_ready(repready),.reply_words(words),
 .remote_valid(remote),.remote_ready(1'b1),.remote_kind(rkind),.remote_value(rvalue),.guide_can_commit(1'b1),.map_can_commit(1'b1),
 .actual_flags(32'd46080),.guide_progress(10'd0),.download_valid(dv),.download_committed(dc),.read_index(9'd0),.song_identity(identity));
 uart_rx #(.CLKS_PER_BIT(16)) receiver(.clk(clk),.rst_n(rst),.rx(tx),.data(byte_out),.valid(rv),.frame_error(bad));
 reg [1023:0] line=0,last_line=0;integer lines=0,controls=0,hello=0,status=0,i,j,k,n;
 always @(posedge clk)if(rst)begin
  if(remote)controls=controls+1;
  if(bad)begin $display("FAIL UART frame");$finish;end
  if(rv)begin
   if(byte_out==10)begin
    last_line=line;line=0;
    if(last_line=="SYNTH/1 CAPS=NOTES,STATUS,GUIDE,KEYMAP MAX_VOICES=32 SAMPLE_RATE=48000 FW=uart-dual-v1 TONE=PIANO_GUITAR")hello=hello+1;
    else if(last_line=="STATUS VOICE_COUNT=0 MAX_VOICE_COUNT=32 STEAL_COUNT=0 SAMPLE_RATE=48000")status=status+1;
    else begin lines=lines+1;$display("CONFIG %0s",last_line);end
   end else line={line[1015:0],byte_out};
  end
 end
 task send;input [1023:0] text;integer length,x,y;
 begin length=0;for(x=0;x<128;x=x+1)if(text[x*8+:8]!=0)length=x+1;
  for(x=length-1;x>=0;x=x-1)begin
   @(negedge clk);rx=0;repeat(16)@(negedge clk);
   for(y=0;y<8;y=y+1)begin rx=text[x*8+y];repeat(16)@(negedge clk);end
   rx=1;repeat(16)@(negedge clk);
  end
 end endtask
 task exchange;input [1023:0] text,expected;integer before_count;
 begin before_count=lines;send(text);wait(lines>before_count);@(negedge clk);
  if(last_line!=expected)begin $display("FAIL reply expected=%0s got=%0s",expected,last_line);$finish;end
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;send("HELLO\n");wait(hello==1);
  exchange("XBEGIN 10 1 4\n","XRESP 10 0 0 0 0 0");
  exchange("XDATA 10 0 1247412225\n","XRESP 10 0 1 0 0 0");
  exchange("XDATA 10 1 90\n","XRESP 10 0 2 0 0 0");
  exchange("XDATA 10 2 1\n","XRESP 10 0 3 0 0 0");
  exchange("XDATA 10 3 3072\n","XRESP 10 0 4 0 0 0");
  exchange("XCOMMIT 10 599881688\n","XRESP 10 0 0 0 0 0");
  if(!dv)begin $display("FAIL wire commit");$finish;end
  // 相邻STATUS与扩展响应必须按整行发送，数值转换空拍不得插入。
  n=lines;send("CTRL 20 3 0\n");send("STATUS?\n");wait(lines>n && status==1);
  exchange("CTRL 20 3 0\n","XRESP 20 0 0 0 0 0");
  if(controls!=1)begin $display("FAIL wire duplicate control");$finish;end
  exchange("GETCFG 30\n","XRESP 30 0 46080 599881688 0 4");
  exchange("XDATA 99 0 1\n","XRESP 99 6 0 0 0 0");
  send("HELLO\n");wait(hello==2);if(!dv)begin $display("FAIL HELLO erased score");$finish;end
  $display("PASS tb_config_uart: actual UART HELLO caps, upload/CRC/commit, whole-line STATUS arbitration, CTRL idempotency, GETCFG, session reset");$finish;
 end
 initial begin #20000000;$display("FAIL config UART timeout lines=%d hello=%d status=%d",lines,hello,status);$finish;end
endmodule
