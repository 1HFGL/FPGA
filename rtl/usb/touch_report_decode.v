// Measured WCH 1A86:E5E3 fixed report layout. Six complete slots are retained;
// Contact Count is not used as the down-state, because release reports keep it.
module touch_report_decode(
    input wire clk,rst_n,connected,
    input wire report_valid,output wire report_ready,
    input wire [415:0] report_data,
    output reg frame_valid,input wire frame_ready,
    output reg [5:0] contact_active,
    output reg [47:0] contact_id,
    output reg [71:0] contact_x,contact_y,
    output reg stream_error
);
    localparam IDLE=0,DECODE=1,CHECK=2,PUBLISH=3;
    reg [1:0] state;
    reg [2:0] index;
    reg [415:0] packet;
    reg bad;
    integer a,b;
    reg duplicate;
    wire tip=packet[8+index*64];
    wire [15:0] raw_x=packet[24+index*64+:16],raw_y=packet[40+index*64+:16];
    wire [22:0] scaled_y={1'd0,raw_y,6'd0}+{4'd0,raw_y,3'd0}+{6'd0,raw_y,1'b0}+{7'd0,raw_y};
    assign report_ready=state==IDLE && connected;
    always @* begin
        duplicate=0;
        for(a=0;a<6;a=a+1)for(b=a+1;b<6;b=b+1)
            if(contact_active[a] && contact_active[b] && contact_id[a*8+:8]==contact_id[b*8+:8])duplicate=1;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;index<=0;packet<=0;bad<=0;frame_valid<=0;stream_error<=0;
            contact_active<=0;contact_id<=0;contact_x<=0;contact_y<=0;
        end else begin
            stream_error<=0;
            if(!connected)begin state<=IDLE;frame_valid<=0;contact_active<=0;end
            else case(state)
                IDLE:if(report_valid && report_ready)begin
                    packet<=report_data;index<=0;bad<=report_data[7:0]!=1 || report_data[415:408]>6;
                    contact_active<=0;state<=DECODE;
                end
                DECODE:begin
                    contact_active[index]<=tip;contact_id[index*8+:8]<=packet[16+index*64+:8];
                    contact_x[index*12+:12]<=tip?(raw_x>=4096?12'd1023:{2'd0,raw_x[11:2]}):12'd0;
                    contact_y[index*12+:12]<=tip?(raw_y>=4096?12'd599:scaled_y[20:9]):12'd0;
                    if(tip && (raw_x>4096 || raw_y>4096))bad<=1;
                    if(index==5)state<=CHECK;else index<=index+1'b1;
                end
                CHECK:begin
                    if(bad || duplicate)begin stream_error<=1;contact_active<=0;state<=IDLE;end
                    else begin frame_valid<=1;state<=PUBLISH;end
                end
                PUBLISH:if(frame_ready)begin frame_valid<=0;state<=IDLE;end
                default:begin frame_valid<=0;stream_error<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
