// 脱机导奏：公版旋律《小星星》前14音，只保存音符索引，不保存录音。
// sys_clk域接收已接受的新起音；按错/松键/长按均不推进，重复音要重新按。
// 音区切换只移动目标音高，乐器切换不重置进度；完成后KEY0复位重练。
// 只产生显示副本，不发音、不阻塞原事件，不依赖USB触摸或视频刷新。
module practice_guide(
    input wire clk,rst_n,
    input wire note_on,
    input wire [6:0] played_note,
    input wire [1:0] octave,
    output wire target_valid,
    output reg [3:0] target_index,
    output wire [6:0] target_note,
    output wire [3:0] progress,
    output reg complete
);
    reg [3:0] step;
    wire [6:0] base=(octave==0)?7'd48:(octave==2)?7'd72:7'd60;
    always @(*)begin
        case(step)
            0,1:target_index=0; // C C
            2,3:target_index=7; // G G
            4,5:target_index=9; // A A
            6:target_index=7;   // G
            7,8:target_index=5; // F F
            9,10:target_index=4;// E E
            11,12:target_index=2;// D D
            default:target_index=0;// C
        endcase
    end
    assign target_note=base+{3'd0,target_index};
    assign target_valid=!complete;
    assign progress=complete ? 4'd14 : step+4'd1;
    always @(posedge clk)begin
        if(!rst_n)begin step<=0;complete<=0;end
        else if(note_on && !complete && played_note==target_note)begin
            if(step==13)complete<=1;
            else step<=step+1'b1;
        end
    end
endmodule
