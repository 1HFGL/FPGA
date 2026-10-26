// 三功能键/触摸/手机共用命令仲裁。所有接口均在50MHz系统域。
// kind: 1音色,2音区,3延音(0翻转/1关/2开),4屏幕开始暂停,
// 5重置,6实体开始重置,7选曲(0翻转/1内置/2下载),8速度绝对值,9速度步进。
module performance_controls #(
    parameter integer DEBOUNCE_CYCLES=100000
)(
    input wire clk,rst_n,
    input wire [2:0] key_n,
    input wire touch_valid,remote_valid,
    output wire touch_ready,remote_ready,
    input wire [3:0] touch_kind,remote_kind,
    input wire [7:0] touch_value,remote_value,
    output reg command_valid,
    input wire command_ready,
    output reg [3:0] command_kind,
    output reg [7:0] command_value,
    output reg sustain
);
    wire [2:0] press;
    reg [2:0] pending;
    reg [1:0] turn;
    reg [1:0] selected;
    reg found;
    reg locked;
    reg [1:0] locked_source;
    reg [3:0] locked_kind;
    reg [7:0] locked_value;
    integer j,s;
    genvar k;
    generate for(k=0;k<3;k=k+1)begin:g_key
        input_sync_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
            .CNT_WIDTH(DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1)) u_debounce(
            .clk(clk),.rst_n(rst_n),.async_in(key_n[k]),.level(),
            .press_pulse(press[k]),.release_pulse());
    end endgenerate
    // 下游在本工程每拍可接收；轮询只隔离各来源的到达顺序。
    always @(*)begin
        selected=0;found=0;
        for(j=0;j<3;j=j+1)begin
            s=turn+j;if(s>=3)s=s-3;
            if(!found && ((s==0 && |pending)||(s==1 && touch_valid)||(s==2 && remote_valid)))begin
                selected=s[1:0];found=1;
            end
        end
        command_valid=found;command_kind=0;command_value=0;
        case(selected)
            0:command_kind=pending[0]?4'd3:pending[1]?4'd7:4'd6;
            1:begin command_kind=touch_kind;command_value=touch_value;end
            2:begin command_kind=remote_kind;command_value=remote_value;end
            default:begin command_kind=0;command_value=0;end
        endcase
        if(locked)begin
            selected=locked_source;
            command_valid=selected==0 || (selected==1?touch_valid:remote_valid);
            command_kind=locked_kind;command_value=locked_value;
        end
    end
    assign touch_ready=command_valid && selected==1 && command_ready;
    assign remote_ready=command_valid && selected==2 && command_ready;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin pending<=0;turn<=0;sustain<=0;locked<=0;locked_source<=0;locked_kind<=0;locked_value<=0;end
        else begin
            if(command_valid && !command_ready && !locked)begin
                locked<=1;locked_source<=selected;locked_kind<=command_kind;locked_value<=command_value;
            end
            if(!command_valid || command_ready)locked<=0;
            pending<=pending|press;
            if(command_valid && command_ready)begin
                turn<=selected==2?2'd0:selected+2'd1;
                if(selected==0)begin
                    if(command_kind==3)pending[0]<=press[0];
                    else if(command_kind==7)pending[1]<=press[1];
                    else pending[2]<=press[2];
                end
                if(command_kind==3)begin
                    if(command_value==0)sustain<=~sustain;
                    else if(command_value<=2)sustain<=command_value==2;
                end
            end
        end
    end
endmodule
