// 静奏界面唯一命中表。绘制器与触点转换器均实例化此模块。
// 坐标已是1024x600有效区像素；矩形统一左闭右开，黑键覆盖白键。
module instrument_ui_map #(parameter integer CONTROL_WIDTH=2, parameter integer EXTENDED=0)(
    input wire [11:0] x,y,
    input wire instrument_guitar,
    output reg note_valid, key_black,
    output reg [3:0] note_index,
    output reg [11:0] key_left,key_right,key_top,key_bottom,
    output reg [CONTROL_WIDTH-1:0] control_kind,
    output reg [1:0] control_value
);
    integer k;
    function [3:0] white_note;
        input integer n;
        begin case(n)
            0:white_note=0;1:white_note=2;2:white_note=4;3:white_note=5;
            4:white_note=7;5:white_note=9;6:white_note=11;default:white_note=12;
        endcase end
    endfunction
    function integer boundary;
        input integer n;
        begin case(n)
            0:boundary=1;1:boundary=2;2:boundary=4;3:boundary=5;default:boundary=6;
        endcase end
    endfunction
    function [3:0] black_note;
        input integer n;
        begin case(n)
            0:black_note=1;1:black_note=3;2:black_note=6;3:black_note=8;default:black_note=10;
        endcase end
    endfunction
    always @(*) begin
        note_valid=0;note_index=0;key_black=0;
        key_left=0;key_right=0;key_top=0;key_bottom=0;
        control_kind=0;control_value=0;
        if(!instrument_guitar)begin
            for(k=0;k<8;k=k+1)
                if(x>=32+k*120 && x<152+k*120 && y>=368 && y<580)begin
                    note_valid=1;note_index=white_note(k);
                    key_left=32+k*120;key_right=152+k*120;key_top=368;key_bottom=580;
                end
            for(k=0;k<5;k=k+1)
                if(x>=32+boundary(k)*120-32 && x<32+boundary(k)*120+32 && y>=368 && y<486)begin
                    note_valid=1;note_index=black_note(k);key_black=1;
                    key_left=32+boundary(k)*120-32;key_right=32+boundary(k)*120+32;
                    key_top=368;key_bottom=486;
                end
        end else begin
            for(k=0;k<13;k=k+1)
                if(x>=32+k*74 && x<100+k*74 && y>=536 && y<584)begin
                    note_valid=1;note_index=k;key_left=32+k*74;key_right=100+k*74;
                    key_top=536;key_bottom=584;
                end
        end
        // 1=明确选择乐器，2=明确选择音区，3=延音翻转。
        if(y>=24 && y<72)begin
            if(x>=760 && x<872)begin control_kind=1;control_value=0;end
            if(x>=880 && x<992)begin control_kind=1;control_value=1;end
        end
        if(y>=100 && y<140)begin
            if(x>=568 && x<632)begin control_kind=2;control_value=0;end
            if(x>=632 && x<696)begin control_kind=2;control_value=1;end
            if(x>=696 && x<760)begin control_kind=2;control_value=2;end
            if(x>=916 && x<992)begin control_kind=3;control_value=0;end
        end
        if(EXTENDED)begin
            if(x>=864 && x<992 && y>=252 && y<292)control_kind=4;
            if(x>=864 && x<992 && y>=300 && y<340)control_kind=5;
            if(y>=164 && y<200)begin
                if(x>=192 && x<320)control_kind=7;
                if(x>=616 && x<656)begin control_kind=9;control_value=0;end
                if(x>=664 && x<704)begin control_kind=9;control_value=1;end
            end
        end
    end
endmodule
