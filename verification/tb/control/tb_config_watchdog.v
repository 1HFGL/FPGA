`timescale 1ns/1ps
// The byte decoder is forced only to place a complete decoded command exactly
// at the watchdog boundary. The protocol/store ready/abort loop remains real.
module tb_config_watchdog;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;
 wire request_valid,request_ready,abort,reply_valid,reply_ready,remote;
 wire [3:0] kind,remote_kind;
 wire [7:0] remote_value;
 wire [31:0] seq,a,b;
 wire [191:0] words;
 wire session,cancel;
 uart_synth_protocol #(.CLKS_PER_BIT(16),.ENABLE_CONFIG(1),.WATCHDOG_CYCLES(32)) protocol(
   .clk(clk),.rst_n(rst_n),.rx(1'b1),.tx(),.event_ready(1'b1),.cancel_ready(1'b1),
   .event_valid(),.event_type(),.event_note(),.event_velocity(),
   .voice_count(6'd0),.max_voice_count(6'd32),.steal_count(32'd0),
   .session_ready(session),.cancel_valid(cancel),
   .config_valid(request_valid),.config_ready(request_ready),.config_kind(kind),
   .config_seq(seq),.config_arg1(a),.config_arg2(b),.config_abort(abort),
   .config_reply_valid(reply_valid),.config_reply_ready(reply_ready),.config_reply_words(words));
 performance_store store(.clk(clk),.rst_n(rst_n),.abort_upload(abort),
   .request_valid(request_valid),.request_ready(request_ready),.request_kind(kind),
   .seq(seq),.arg1(a),.arg2(b),.reply_valid(reply_valid),.reply_ready(reply_ready),.reply_words(words),
   .remote_valid(remote),.remote_ready(1'b1),.remote_kind(remote_kind),.remote_value(remote_value),
   .guide_can_commit(1'b1),.map_can_commit(1'b1),.actual_flags(32'd0),.guide_progress(10'd0),.read_index(9'd0),
   .download_valid(),.download_committed(),.download_count(),.download_bpm(),
   .read_mask(),.read_duration(),.keymap(),.song_identity(),.map_identity());
 integer accepted=0,checks=0;
 always @(posedge clk)if(rst_n && request_valid && request_ready)accepted=accepted+1;
 task initialize;
 begin
   rst_n=0;
   force protocol.u_line.cmd_valid=0;
   force protocol.u_line.cmd=12;
   force protocol.u_line.fields=2;
   force protocol.u_line.arg0=32'd99;
   force protocol.u_line.arg1=0;
   force protocol.u_line.arg2=0;
   force protocol.u_line.bad_line=0;
   force protocol.u_line.bad_number=0;
   force protocol.u_line.sequence_valid=1;
   repeat(3)@(negedge clk);
   rst_n=1;protocol.session_ready=1;protocol.health_counter=30;
 end
 endtask
 task alive;
 begin
   if(abort || !session)begin
     $display("FAIL config watchdog valid command aborted at expiry ready=%b valid=%b health=%d",request_ready,request_valid,protocol.health_counter);$finish;
   end
   checks=checks+1;
 end
 endtask
 initial begin
   initialize;
   // Enter expiry with no command, then present valid GETCFG in the same
   // cycle before its active edge. This exposes the original bistable loop.
   @(negedge clk);protocol.health_counter=31;
   #1;force protocol.u_line.cmd_valid=1;
   #1;alive;
   if(!request_valid || !request_ready)begin $display("FAIL config watchdog ready request lost");$finish;end
   @(posedge clk);#1;alive;
   if(protocol.health_counter!=0 || accepted!=1)begin $display("FAIL config watchdog ready health/accept");$finish;end
   @(negedge clk);force protocol.u_line.cmd_valid=0;
   initialize;
   // The backend is legitimately busy performing CRC; return BUSY but retain
   // the live session and existing upload rather than feeding back abort.
   force store.state=3'd1;
   @(negedge clk);protocol.health_counter=31;
   #1;force protocol.u_line.cmd_valid=1;
   #1;alive;
   if(request_valid || request_ready || !protocol.error_req || protocol.error_code!=3)begin
     $display("FAIL config watchdog BUSY response");$finish;
   end
   @(posedge clk);#1;alive;
   if(protocol.health_counter!=0)begin $display("FAIL config watchdog BUSY did not refresh");$finish;end
   release store.state;
   initialize;
   @(negedge clk);protocol.health_counter=31;
   force protocol.u_line.cmd_valid=1;force protocol.u_line.bad_number=1;
   #1;if(!abort || request_valid)begin $display("FAIL config watchdog malformed refreshed");$finish;end
   @(posedge clk);#1;if(session || !cancel)begin $display("FAIL config watchdog malformed expiry");$finish;end
   checks=checks+1;
   initialize;
   @(negedge clk);protocol.health_counter=31;
   #1;if(!abort)begin $display("FAIL config watchdog idle did not expire");$finish;end
   @(posedge clk);#1;if(session || !cancel)begin $display("FAIL config watchdog idle cancel");$finish;end
   checks=checks+1;
   $display("PASS tb_config_watchdog: ready and BUSY deadline keepalive, malformed and idle expiry, checks=%0d",checks);$finish;
 end
 initial begin #10000;$display("FAIL config watchdog timeout");$finish;end
endmodule
