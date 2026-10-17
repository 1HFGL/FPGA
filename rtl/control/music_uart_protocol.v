// 本版控制协议：电脑只发音符，波形/ADSR仍在FPGA实时计算。
// 参数缩短仅供仿真；默认50MHz下半行250ms、会话3s。
module music_uart_protocol #(
    parameter integer CLKS_PER_BIT=434,
    parameter integer LINE_TIMEOUT_CYCLES=12500000,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter integer VOICES=4
)(
    input wire clk,rst_n,rx,output wire tx,
    output wire event_valid,input wire event_ready,
    output wire event_type,output wire [6:0] event_note,event_velocity,
    output reg cancel_valid,input wire cancel_ready,
    input wire [5:0] voice_count,max_voice_count,input wire [31:0] steal_count,
    output reg session_ready,
    input wire control_ready,
    input wire [6:0] target_volume,input wire [10:0] target_bend,
    output wire control_valid,output wire [6:0] control_volume,output wire [10:0] control_bend,
    output reg selected_preset,output wire event_preset
);
    wire [7:0] rx_data,qbyte,tx_data;
    wire rx_valid,rx_bad,rx_ready,qvalid,tx_valid,tx_ready;
    reg rx_flush;
    wire rx_fault=rx_bad || (rx_valid && !rx_ready && !rx_flush);
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx(.clk(clk),.rst_n(rst_n),.rx(rx),
        .data(rx_data),.valid(rx_valid),.frame_error(rx_bad));
    uart_fifo #(.WIDTH(8),.ADDR_BITS(6)) u_rx_fifo(.clk(clk),.rst_n(rst_n),.flush(rx_flush),
        .in_valid(rx_valid),.in_ready(rx_ready),.in_data(rx_data),
        .out_valid(qvalid),.out_ready(1'b1),.out_data(qbyte),.level());
    wire cv,bl,bn,sv;
    wire [3:0] command,fields;
    wire [31:0] a,b,c;
    music_uart_line_rx #(.TIMEOUT_CYCLES(LINE_TIMEOUT_CYCLES)) u_line(
        .clk(clk),.rst_n(rst_n),.byte_valid(qvalid),.byte_data(qbyte),.bad_byte(rx_fault || rx_flush),
        .cmd_valid(cv),.cmd(command),.fields(fields),.arg0(a),.arg1(b),.arg2(c),
        .bad_line(bl),.bad_number(bn),.sequence_valid(sv));
    reg hello_req,status_req,error_req,legal,note_req,cancel_req;
    reg [2:0] error_code;
    reg [31:0] error_seq;
    reg [31:0] health_counter;
    wire event_space;
    assign control_valid=cv && command==8 && legal;
    assign control_volume=a[6:0];assign control_bend=b[10:0];
    wire watchdog=session_ready && health_counter==WATCHDOG_CYCLES-1 && !legal;
    wire flush_events=cancel_req || rx_fault || watchdog;
    wire [15:0] queued_event;
    wire [4:0] event_level;
    uart_fifo #(.WIDTH(16),.ADDR_BITS(4)) u_events(.clk(clk),.rst_n(rst_n),.flush(flush_events),
        .in_valid(note_req),.in_ready(event_space),.in_data({selected_preset,command==2 && b!=0,a[6:0],command==2 ? b[6:0] : 7'd0}),
        .out_valid(event_valid),.out_ready(event_ready),.out_data(queued_event),.level(event_level));
    assign {event_preset,event_type,event_note,event_velocity}=queued_event;
    // 协议判定与FIFO空间分离，避免flush->ready->flush组合环。
    // event_space在flush时为0；只有合法音符才需要检查原始队列容量。
    wire raw_space=(event_level<16);
    always @* begin
        hello_req=0; status_req=0; error_req=0; error_code=0; error_seq=0;
        legal=0; note_req=0; cancel_req=0;
        if(cv) begin
            if(bl) begin error_req=1; error_code=1; end
            else case(command)
                1,4,5: begin
                    if(fields!=1) begin error_req=1; error_code=1; end
                    else begin
                        legal=1;
                        if(command==1) begin hello_req=1; cancel_req=1; end
                        if(command==4) cancel_req=1;
                        if(command==5) status_req=1;
                    end
                end
                2,3: begin
                    if(bn || (command==2 && fields!=4) || (command==3 && fields!=3)) begin error_req=1; error_code=1; end
                    else if(a>127 || (command==2 && (b>127 || c!=0)) || (command==3 && b!=0)) begin error_req=1; error_code=2; end
                    else if(!session_ready) begin error_req=1; error_code=4; end
                    else begin
                        legal=1;
                        if(!raw_space) begin cancel_req=1; error_req=1; error_code=3; end
                        else note_req=1;
                    end
                end
                7: begin
                    if(bn || fields!=2) begin error_req=1; error_code=1; end
                    else if(a>1) begin error_req=1; error_code=2; end
                    else if(!session_ready) begin error_req=1; error_code=4; end
                    else begin legal=1; status_req=1; end
                end
                8: begin
                    if(bn || fields!=3) begin error_req=1;error_code=1;end
                    else if(a>127 || b>1024) begin error_req=1;error_code=2;end
                    else if(!session_ready) begin error_req=1;error_code=4;end
                    else if(!control_ready) begin error_req=1;error_code=3;end
                    else begin legal=1;status_req=1;end
                end
                default: begin
                    error_req=1; error_code=5;
                    if(command==6 && sv) error_seq=a;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rx_flush<=0; cancel_valid<=0; health_counter<=0; session_ready<=0; selected_preset<=1; end
        else begin
            rx_flush<=rx_fault;
            if(cv && command==7 && legal)selected_preset<=a[0];
            if(cancel_valid && cancel_ready) cancel_valid<=0;
            if(flush_events) cancel_valid<=1;
            if(!session_ready || legal) health_counter<=0;
            else if(!watchdog) health_counter<=health_counter+1'b1;
            if(watchdog) begin session_ready<=0; health_counter<=0; end
            if(hello_req) session_ready<=1;
        end
    end
    music_uart_reply_tx #(.VOICES(VOICES)) u_replies(.clk(clk),.rst_n(rst_n),.hello_req(hello_req),.status_req(status_req),
        .error_req(error_req),.voice_count(voice_count),.max_voice_count(max_voice_count),.steal_count(steal_count),
        .selected_preset((cv && command==7 && legal)?a[0]:selected_preset),
        .target_volume(control_valid?a[6:0]:target_volume),.target_bend(control_valid?b[10:0]:target_bend),
        .error_sequence(error_seq),.error_code(error_code),.tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready));
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx(.clk(clk),.rst_n(rst_n),.data(tx_data),
        .valid(tx_valid),.ready(tx_ready),.tx(tx));
endmodule
