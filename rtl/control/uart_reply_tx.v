// 四个描述槽：HELLO保留一槽，STATUS一槽（最新快照），ERROR两槽。
// 整行串行化，不能在一行中插入新握手；拥塞诊断允许丢弃，不阻塞演奏。
// 32拍移位加3转换BCD，避免32位组合除10拖累50MHz时序。
module uart_reply_tx #(parameter integer FIXED_PIANO=0)(
    input wire clk,rst_n,
    input wire hello_req,status_req,error_req,
    input wire [5:0] voice_count,max_voice_count,input wire [31:0] steal_count,
    input wire [31:0] error_sequence,input wire [2:0] error_code,
    output wire [7:0] tx_data,output wire tx_valid,input wire tx_ready
);
    // 只报告编译进位流的真实音色；没有CONFIG/APPLIED，不能暗示滑条生效。
    localparam integer HELLO_LENGTH=FIXED_PIANO ? 91 : 90;
    localparam [8*91-1:0] HELLO_TEXT=FIXED_PIANO ?
        "SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-piano-v1 TONE=FIXED_PIANO\n" :
        "SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE\n";
    reg hp,sp,e0,e1;
    reg [5:0] sc,sm;
    reg [31:0] ss,seq0,seq1;
    reg [2:0] ec0,ec1,reason;
    reg [1:0] kind;
    reg [2:0] state,part;
    reg [7:0] pos;
    reg [5:0] convert_bit;
    reg [31:0] binary0,binary1,binary2;
    reg [39:0] bcd0,bcd1,bcd2;
    reg [39:0] corrected0,corrected1,corrected2;
    reg [3:0] digit_index;
    reg started;
    reg [7:0] character,text_length;
    reg [39:0] selected_bcd;
    wire number_state=state==3;
    wire consuming_error=state==0 && !hp && !sp && e0;
    wire skip_zero=number_state && !started && digit_index!=0 && selected_bcd[digit_index*4 +: 4]==0;
    assign tx_valid=(state==2 || state==3) && !skip_zero;
    assign tx_data=number_state ? 8'd48+{4'd0,selected_bcd[digit_index*4 +: 4]} : character;
    function [7:0] text_char;
        input [8*91-1:0] text;
        input integer len,index;
        begin text_char=text[(len-1-index)*8 +: 8]; end
    endfunction
    integer i;
    always @* begin
        corrected0=bcd0; corrected1=bcd1; corrected2=bcd2;
        for(i=0;i<10;i=i+1) begin
            if(bcd0[i*4 +: 4]>=5) corrected0[i*4 +: 4]=bcd0[i*4 +: 4]+4'd3;
            if(bcd1[i*4 +: 4]>=5) corrected1[i*4 +: 4]=bcd1[i*4 +: 4]+4'd3;
            if(bcd2[i*4 +: 4]>=5) corrected2[i*4 +: 4]=bcd2[i*4 +: 4]+4'd3;
        end
        selected_bcd=bcd0;
        if(part==1) selected_bcd=bcd1;
        if(part==2) selected_bcd=bcd2;
        character=10; text_length=1;
        if(kind==0) begin text_length=HELLO_LENGTH; character=text_char(HELLO_TEXT,HELLO_LENGTH,pos); end
        else if(kind==1) begin
            case(part)
                0: begin text_length=19; character=text_char("STATUS VOICE_COUNT=",19,pos); end
                1: begin text_length=17; character=text_char(" MAX_VOICE_COUNT=",17,pos); end
                2: begin text_length=13; character=text_char(" STEAL_COUNT=",13,pos); end
                default: begin text_length=19; character=text_char(" SAMPLE_RATE=48000\n",19,pos); end
            endcase
        end else begin
            case(part)
                0: begin text_length=6; character=text_char("ERROR ",6,pos); end
                default: case(reason)
                    1: begin text_length=9; character=text_char(" BAD_CMD\n",9,pos); end
                    2: begin text_length=7; character=text_char(" RANGE\n",7,pos); end
                    3: begin text_length=6; character=text_char(" BUSY\n",6,pos); end
                    4: begin text_length=11; character=text_char(" NOT_READY\n",11,pos); end
                    default: begin text_length=13; character=text_char(" UNSUPPORTED\n",13,pos); end
                endcase
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            hp<=0; sp<=0; e0<=0; e1<=0; sc<=0; sm<=0; ss<=0;
            seq0<=0; seq1<=0; ec0<=0; ec1<=0; reason<=0;
            kind<=0; state<=0; part<=0; pos<=0; convert_bit<=0;
            binary0<=0; binary1<=0; binary2<=0; bcd0<=0; bcd1<=0; bcd2<=0;
            digit_index<=0; started<=0;
        end else begin
            case(state)
                0: begin
                    part<=0; pos<=0; bcd0<=0; bcd1<=0; bcd2<=0; convert_bit<=0;
                    if(hp) begin hp<=0; kind<=0; state<=2; end
                    else if(sp) begin
                        sp<=0; kind<=1; binary0<={26'd0,sc}; binary1<={26'd0,sm}; binary2<=ss; state<=1;
                    end else if(e0) begin
                        e0<=e1; seq0<=seq1; ec0<=ec1; e1<=0;
                        kind<=2; binary0<=seq0; binary1<=0; binary2<=0; reason<=ec0; state<=1;
                    end
                end
                1: begin
                    bcd0<={corrected0[38:0],binary0[31]}; binary0<={binary0[30:0],1'b0};
                    bcd1<={corrected1[38:0],binary1[31]}; binary1<={binary1[30:0],1'b0};
                    bcd2<={corrected2[38:0],binary2[31]}; binary2<={binary2[30:0],1'b0};
                    if(convert_bit==31) state<=2; else convert_bit<=convert_bit+1'b1;
                end
                2: if(tx_ready) begin
                    if(pos==text_length-1) begin
                        pos<=0;
                        if(kind==0 || kind==1 && part==3 || kind==2 && part==1) state<=0;
                        else begin state<=3; digit_index<=9; started<=0; end
                    end else pos<=pos+1'b1;
                end
                3: if(skip_zero || tx_ready) begin
                    if(!skip_zero) started<=1;
                    if(digit_index==0) begin state<=2; part<=part+1'b1; pos<=0; end
                    else digit_index<=digit_index-1'b1;
                end
                default: state<=0;
            endcase
            // 收包与发包独立；同拍有更新时新快照优先保留。
            if(hello_req) hp<=1;
            if(status_req) begin sp<=1; sc<=voice_count; sm<=max_voice_count; ss<=steal_count; end
            if(error_req) begin
                if(!e0 || consuming_error && !e1) begin e0<=1; seq0<=error_sequence; ec0<=error_code; end
                else if(!e1 || consuming_error) begin e1<=1; seq1<=error_sequence; ec1<=error_code; end
                // 两槽均满丢弃诊断；音乐路径仍继续服务。
            end
        end
    end
endmodule
