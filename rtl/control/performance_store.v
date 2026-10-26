// BLE配置事务：双bank曲谱、原子键位表、逐位CRC。只接收已检查格式的扩展命令。
// XRESP seq code value0 value1 value2 value3；code=0成功/2范围/3忙/4序号/5CRC/6无事务/7无曲。
// RAM不整体复位；valid屏蔽未提交内容。取消事务不能清掉活动配置。
module performance_store #(
 parameter integer TIMEOUT_CYCLES=250000000
)(
 input wire clk,rst_n,abort_upload,
 input wire request_valid,output wire request_ready,
 input wire [3:0] request_kind,input wire [31:0] seq,arg1,arg2,
 output reg reply_valid,input wire reply_ready,output reg [191:0] reply_words,
 output wire remote_valid,input wire remote_ready,
 output reg [3:0] remote_kind,output reg [7:0] remote_value,
 input wire guide_can_commit,map_can_commit,
 input wire [31:0] actual_flags,input wire [9:0] guide_progress,
 output reg download_valid,download_committed,
 output reg [9:0] download_count,output reg [7:0] download_bpm,
 input wire [8:0] read_index,output wire [36:0] read_mask,output wire [15:0] read_duration,
 output reg [103:0] keymap,
 output reg [31:0] song_identity,map_identity
);
 localparam IDLE=0,CRC=1,DUP_CHECK=3,CONTROL=4;
 reg [2:0] state;
 reg active,object_map,bank;
 reg [31:0] upload_seq,crc,crc_work,age;
 reg [10:0] words,received;
 reg [5:0] bit_count;
 reg [31:0] staged_bpm;
 reg [103:0] staged_map;
 reg [31:0] req_seq,req_word;
 reg [10:0] req_index;
 reg committed_valid,control_cached;
 reg [31:0] committed_seq,committed_crc,control_seq;
 reg [3:0] last_control_kind;
 reg [7:0] last_control_value;
 reg [31:0] low_mem[0:1023],high_mem[0:1023];
 reg [31:0] play_low,play_high,duplicate_low,duplicate_high;
 wire accepted=request_valid && request_ready;
 wire [10:0] segment_words=words-11'd2;
 wire [3:0] mapping_index=arg1[3:0]-4'd1;
 wire [3:0] duplicate_map_index=req_index[3:0]-4'd1;
 wire [10:0] payload_index=arg1[10:0]-11'd2;
 wire [9:0] staging_address={!bank,payload_index[9:1]};
 wire score_write=accepted && request_kind==8 && active && seq==upload_seq && !object_map &&
     arg1=={21'd0,received} && arg1>=2 && arg1<{21'd0,words} &&
     (!arg1[0] || (arg2[31:21]==0 && arg2[20:5]!=0));
 // 两个双口RAM的A口用于暂存写/重复包核验，B口始终读已提交bank。
 always @(posedge clk)begin
   if(score_write && !arg1[0])low_mem[staging_address]<=arg2;
   if(score_write && arg1[0])high_mem[staging_address]<=arg2;
   // 显式写优先旁路，避免Gowin推断本器件不支持的READ_FIRST模式。
   duplicate_low<=(score_write && !arg1[0])?arg2:low_mem[staging_address];
   duplicate_high<=(score_write && arg1[0])?arg2:high_mem[staging_address];
   play_low<=low_mem[{bank,read_index}];play_high<=high_mem[{bank,read_index}];
 end
 assign read_mask=download_valid?{play_high[4:0],play_low}:37'd0;
 assign read_duration=download_valid?play_high[20:5]:16'd96;
 wire expired=active && age==TIMEOUT_CYCLES-1;
 assign request_ready=state==IDLE && !reply_valid && !abort_upload && !expired;
 assign remote_valid=state==CONTROL && !abort_upload;
 wire [31:0] crc_next=(crc_work>>1)^(crc_work[0]?32'hedb88320:32'd0);
 wire ctrl_in_range=(arg1==1 && arg2<2)||(arg1==2 && arg2<3)||(arg1==3 && arg2<=2)||
   ((arg1==4 || arg1==5 || arg1==6) && arg2==0)||(arg1==7 && arg2<=2)||
   (arg1==8 && arg2>=30 && arg2<=240)||(arg1==9 && arg2<2);
 reg [31:0] duplicate_expected;
 always @(*)begin
   duplicate_expected=0;
   if(object_map)begin
     if(req_index==0)duplicate_expected=32'h4a4d0001;
     else if(req_index<=13)duplicate_expected={24'd0,staged_map[duplicate_map_index*8+:8]};
   end else if(req_index==0)duplicate_expected=32'h4a5a0001;
   else if(req_index==1)duplicate_expected=staged_bpm;
   else duplicate_expected=req_index[0]?duplicate_high:duplicate_low;
 end
 task respond;
   input [31:0] id,code,v0,v1,v2,v3;
   begin reply_valid<=1;reply_words<={v3,v2,v1,v0,code,id};end
 endtask
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;active<=0;object_map<=0;bank<=0;upload_seq<=0;crc<=32'hffffffff;crc_work<=0;age<=0;
   words<=0;received<=0;bit_count<=0;staged_bpm<=90;staged_map<=0;req_seq<=0;req_word<=0;req_index<=0;
   committed_valid<=0;committed_seq<=0;committed_crc<=0;control_cached<=0;control_seq<=0;
   last_control_kind<=0;last_control_value<=0;remote_kind<=0;remote_value<=0;
   reply_valid<=0;reply_words<=0;download_valid<=0;download_committed<=0;download_count<=0;download_bpm<=90;
   song_identity<=0;map_identity<=0;
   for(i=0;i<13;i=i+1)keymap[i*8+:8]<=i[7:0];
  end else begin
   download_committed<=0;
   if(reply_valid && reply_ready)reply_valid<=0;
   if(active)begin
     if(expired)begin active<=0;age<=0;end
     else age<=age+1'b1;
   end else age<=0;
   if(state==CRC)begin
     crc_work<=crc_next;
     if(bit_count==31)begin crc<=crc_next;received<=received+1'b1;state<=IDLE;age<=0;
       respond(req_seq,0,{21'd0,received}+32'd1,0,0,0);end
     else bit_count<=bit_count+1'b1;
   end
   if(state==DUP_CHECK)begin
     state<=IDLE;
     if(duplicate_expected==req_word)begin age<=0;respond(req_seq,0,{21'd0,received},0,0,0);end
     else respond(req_seq,4,{21'd0,received},0,0,0);
   end
   if(remote_valid && remote_ready)begin
     state<=IDLE;control_cached<=1;control_seq<=req_seq;
     last_control_kind<=remote_kind;last_control_value<=remote_value;
     respond(req_seq,0,0,0,0,0);
   end
   if(accepted)begin
    case(request_kind)
     7:begin // XBEGIN；同号同长度重试不清空已收字
       if(active)begin
         if(seq==upload_seq && arg1==(object_map?32'd2:32'd1) && arg2=={21'd0,words})begin
           age<=0;respond(seq,0,{21'd0,received},0,0,0);
         end else respond(seq,3,{21'd0,received},0,0,0);
       end else if(committed_valid && seq==committed_seq)respond(seq,4,0,0,0,0);
       else if((arg1==1 && arg2>=4 && arg2<=1026 && !arg2[0]) || (arg1==2 && arg2==14))begin
         active<=1;object_map<=arg1==2;upload_seq<=seq;words<=arg2[10:0];received<=0;crc<=32'hffffffff;age<=0;
         respond(seq,0,0,0,0,0);
       end else respond(seq,2,0,0,0,0);
     end
     8:begin
       if(!active)respond(seq,6,0,0,0,0);
       else if(seq!=upload_seq || arg1>{21'd0,received} || arg1>={21'd0,words})respond(seq,4,{21'd0,received},0,0,0);
       else if(arg1<{21'd0,received})begin
         req_seq<=seq;req_word<=arg2;req_index<=arg1[10:0];state<=DUP_CHECK;
         // A口在本沿读回指定索引，下一拍DUP_CHECK看到该字。
       end else if((arg1==0 && arg2!=(object_map?32'h4a4d0001:32'h4a5a0001)) ||
           (object_map && arg1!=0 && !(arg2<=12 || arg2==255)) ||
           (!object_map && arg1==1 && (arg2<30 || arg2>240)) ||
           (!object_map && arg1>=2 && arg1[0] && (arg2[31:21]!=0 || arg2[20:5]==0)))respond(seq,2,{21'd0,received},0,0,0);
       else begin
         if(object_map && arg1!=0)staged_map[mapping_index*8+:8]<=arg2[7:0];
         if(!object_map && arg1==1)staged_bpm<=arg2;
         req_seq<=seq;crc_work<=crc^arg2;bit_count<=0;state<=CRC;age<=0;
       end
     end
     9:begin
       if(!active && committed_valid && seq==committed_seq && arg1==committed_crc)respond(seq,0,0,0,0,0);
       else if(!active)respond(seq,6,0,0,0,0);
       else if(seq!=upload_seq || received!=words)respond(seq,4,{21'd0,received},0,0,0);
       else if(arg1!=(crc^32'hffffffff))respond(seq,5,0,0,0,0);
       else if((object_map && !map_can_commit)||(!object_map && !guide_can_commit))respond(seq,3,0,0,0,0);
       else begin
         active<=0;committed_valid<=1;committed_seq<=seq;committed_crc<=arg1;
         if(object_map)begin keymap<=staged_map;map_identity<=arg1;end
         else begin bank<=!bank;download_valid<=1;download_committed<=1;download_count<=segment_words[10:1];
           download_bpm<=staged_bpm[7:0];song_identity<=arg1;end
         respond(seq,0,0,0,0,0);
       end
     end
     10:begin
       if(active && seq!=upload_seq)respond(seq,4,0,0,0,0);
       else begin active<=0;respond(seq,0,0,0,0,0);end
     end
     11:begin
       if(control_cached && seq==control_seq)begin
         if(arg1=={28'd0,last_control_kind} && arg2=={24'd0,last_control_value})respond(seq,0,0,0,0,0);
         else respond(seq,4,0,0,0,0);
       end else if(!ctrl_in_range)respond(seq,2,0,0,0,0);
       else if(arg1==7 && (arg2==2 || (arg2==0 && !actual_flags[4])) && !download_valid)respond(seq,7,0,0,0,0);
       else begin req_seq<=seq;remote_kind<=arg1[3:0];remote_value<=arg2[7:0];state<=CONTROL;end
     end
     12:respond(seq,0,actual_flags,song_identity,map_identity,
           {6'd0,guide_progress,active,object_map,3'd0,received});
     default:respond(seq,2,0,0,0,0);
    endcase
   end
   // 取消优先于同拍完成，不发布半包。缓存响应跨断线不能继续执行CTRL。
   if(abort_upload)begin active<=0;state<=IDLE;reply_valid<=0;control_cached<=0;committed_valid<=0;age<=0;end
  end
 end
endmodule
