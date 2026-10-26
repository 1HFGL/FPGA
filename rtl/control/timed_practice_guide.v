// 96 PPQN固定节拍导奏，仅生成显示目标，不给音频核心发事件。
// 曲谱读口同步读，提前读取下一段；每段至少1刻度，50MHz有足够预取时间。
module timed_practice_guide #(
    parameter integer MS_CYCLES=50000
)(
    input wire clk,rst_n,command_valid,
    input wire [3:0] command_kind,
    input wire [7:0] command_value,
    input wire download_valid,download_committed,
    input wire [9:0] download_count,
    input wire [7:0] download_bpm,
    output wire [8:0] read_index,
    input wire [36:0] read_mask,
    input wire [15:0] read_duration,
    output reg selected_download,
    output reg [2:0] state,
    output reg [7:0] bpm,
    output reg [9:0] progress,
    output reg [1:0] beat,
    output reg [36:0] target,
    output reg missing_download,
    output wire can_commit
);
    localparam READY=0,COUNT_IN=1,RUNNING=2,PAUSED=3,COMPLETE=4;
    localparam integer MW=MS_CYCLES>1?$clog2(MS_CYCLES):1;
    reg [MW-1:0] ms_counter;
    reg [16:0] phase;
    reg [6:0] tick_in_beat;
    reg [15:0] remaining;
    reg [2:0] resume_state;
    reg [7:0] pending_bpm;
    reg tempo_pending;
    wire running=state==COUNT_IN || state==RUNNING;
    wire advancing=running && !(command_valid && command_kind==4);
    wire ms_enable=ms_counter==MS_CYCLES-1;
    wire [16:0] increment=({9'd0,bpm}<<6)+({9'd0,bpm}<<5);
    wire [16:0] phase_sum=phase+increment;
    wire tick=advancing && ms_enable && phase_sum>=17'd60000;
    wire [9:0] total=selected_download?download_count:10'd42;
    assign can_commit=state==READY || state==COMPLETE;
    // 预备期间预取第0段；演奏期间预取下一段。
    assign read_index=(state==RUNNING || (state==PAUSED && resume_state==RUNNING))?
        progress[8:0]+9'd1:9'd0;
    function [3:0] twinkle;
        input [8:0] n;
        begin case(n)
            0,1,13,28,29,41:twinkle=0;
            9,10,37,38:twinkle=4;
            7,8,35,36:twinkle=5;
            4,5,32,33:twinkle=9;
            11,12,20,25,26,27,39,40:twinkle=2;
            default:twinkle=7;
        endcase end
    endfunction
    // 小星星中间两句：G G F F E E D。
    function [3:0] builtin_note;
        input [8:0] n;
        begin
            case(n)
                16,17,23,24:builtin_note=5;
                18,19,25,26:builtin_note=4;
                20,27:builtin_note=2;
                default:builtin_note=twinkle(n);
            endcase
        end
    endfunction
    wire [36:0] next_mask=selected_download?read_mask:(37'd1<<(12+builtin_note(read_index)));
    wire [15:0] next_duration=selected_download?read_duration:
        ((read_index==6 || read_index==13 || read_index==20 || read_index==27 || read_index==34 || read_index==41)?16'd192:16'd96);
    wire [7:0] tempo_base=tempo_pending?pending_bpm:bpm;
    reg [7:0] requested_bpm;
    always @(*)begin
        requested_bpm=command_value;
        if(command_kind==9)begin
            if(command_value==0)requested_bpm=(tempo_base<35)?8'd30:tempo_base-8'd5;
            else requested_bpm=(tempo_base>235)?8'd240:tempo_base+8'd5;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            ms_counter<=0;phase<=0;tick_in_beat<=0;remaining<=0;resume_state<=READY;
            selected_download<=0;state<=READY;bpm<=90;pending_bpm<=90;tempo_pending<=0;
            progress<=0;beat<=0;target<=0;missing_download<=0;
        end else begin
            if(advancing)begin
                if(ms_enable)ms_counter<=0;else ms_counter<=ms_counter+1'b1;
                if(ms_enable)phase<=tick?phase_sum-17'd60000:phase_sum;
            end
            if(tick)begin
                if(tick_in_beat==95)begin
                    tick_in_beat<=0;beat<=beat+1'b1;
                    if(tempo_pending)begin bpm<=pending_bpm;tempo_pending<=0;end
                    if(state==COUNT_IN && beat==3)begin
                        state<=RUNNING;target<=next_mask;remaining<=next_duration;
                    end
                end else tick_in_beat<=tick_in_beat+1'b1;
                if(state==RUNNING)begin
                    if(remaining<=1)begin
                        if(progress+10'd1>=total)begin state<=COMPLETE;progress<=total;target<=0;end
                        else begin progress<=progress+1'b1;remaining<=next_duration;target<=next_mask;end
                    end else remaining<=remaining-1'b1;
                end
            end
            if(download_committed)begin
                state<=READY;progress<=0;target<=0;phase<=0;tick_in_beat<=0;beat<=0;ms_counter<=0;tempo_pending<=0;
                if(selected_download)bpm<=download_bpm;
            end
            if(command_valid)begin
                case(command_kind)
                    4:begin
                        if(state==READY || state==COMPLETE)begin
                            state<=COUNT_IN;progress<=0;beat<=0;target<=0;phase<=0;tick_in_beat<=0;ms_counter<=0;
                        end else if(state==PAUSED)state<=resume_state;
                        else begin state<=PAUSED;resume_state<=state;end
                    end
                    5,6:begin
                        state<=(command_kind==6 && (state==READY || state==COMPLETE))?COUNT_IN:READY;
                        progress<=0;target<=0;phase<=0;tick_in_beat<=0;beat<=0;ms_counter<=0;
                        if(tempo_pending)begin bpm<=pending_bpm;tempo_pending<=0;end
                    end
                    7:begin
                        if((command_value==2 || (command_value==0 && !selected_download)) && !download_valid)
                            missing_download<=1;
                        else if(command_value<=2)begin
                            selected_download<=command_value==0?!selected_download:command_value==2;
                            bpm<=(command_value==2 || (command_value==0 && !selected_download))?download_bpm:8'd90;
                            state<=READY;progress<=0;target<=0;phase<=0;tick_in_beat<=0;beat<=0;ms_counter<=0;
                            tempo_pending<=0;missing_download<=0;
                        end
                    end
                    8,9:if(requested_bpm>=30 && requested_bpm<=240)begin
                        if(running)begin pending_bpm<=requested_bpm;tempo_pending<=1;end
                        else begin bpm<=requested_bpm;tempo_pending<=0;end
                    end
                    default:begin end
                endcase
            end
        end
    end
endmodule
