`timescale 1ns/1ps
// 穷举完整12位坐标，而不只验证可见1024x600区域。
// 参考模型用除法/明确区间描述；它只用于仿真，不会进入综合。
// 可额外定义UI_MAP_REFERENCE，同时比较build内冻结的修改前RTL。
module tb_ui_map_equivalence;
    reg [11:0] x,y;
    reg instrument_guitar;
    wire note_valid,key_black;
    wire [3:0] note_index;
    wire [11:0] key_left,key_right,key_top,key_bottom;
    wire [1:0] control_kind,control_value;
    wire [57:0] actual={note_valid,key_black,note_index,key_left,key_right,
                        key_top,key_bottom,control_kind,control_value};
    instrument_ui_map dut(.x(x),.y(y),.instrument_guitar(instrument_guitar),
        .note_valid(note_valid),.key_black(key_black),.note_index(note_index),
        .key_left(key_left),.key_right(key_right),.key_top(key_top),.key_bottom(key_bottom),
        .control_kind(control_kind),.control_value(control_value));
`ifdef UI_MAP_REFERENCE
    wire [57:0] reference;
    instrument_ui_map_reference old(.x(x),.y(y),.instrument_guitar(instrument_guitar),
        .note_valid(reference[57]),.key_black(reference[56]),.note_index(reference[55:52]),
        .key_left(reference[51:40]),.key_right(reference[39:28]),
        .key_top(reference[27:16]),.key_bottom(reference[15:4]),
        .control_kind(reference[3:2]),.control_value(reference[1:0]));
`endif
    reg passed;
    integer samples,piano_count,black_count,guitar_count,control_count;
    integer xx,yy,mode;
    reg [57:0] expected;

    function [57:0] model;
        input [11:0] px,py;
        input guitar;
        reg valid,black;
        reg [3:0] note;
        reg [11:0] left,right,top,bottom;
        reg [1:0] kind,value;
        integer slot,boundary;
        begin
            valid=0;black=0;note=0;left=0;right=0;top=0;bottom=0;
            kind=0;value=0;slot=0;boundary=0;
            if(!guitar && px>=32 && px<992 && py>=368 && py<580)begin
                slot=(px-32)/120;
                valid=1;left=32+slot*120;right=left+120;top=368;bottom=580;
                case(slot)
                    0:note=0;1:note=2;2:note=4;3:note=5;
                    4:note=7;5:note=9;6:note=11;7:note=12;
                    default:note=0;
                endcase
                // 五个黑键区间。E-F和B-C之间不添加黑键。
                if(py<486)begin
                    if(px>=120 && px<184)begin boundary=1;note=1;end
                    if(px>=240 && px<304)begin boundary=2;note=3;end
                    if(px>=480 && px<544)begin boundary=4;note=6;end
                    if(px>=600 && px<664)begin boundary=5;note=8;end
                    if(px>=720 && px<784)begin boundary=6;note=10;end
                    if(boundary!=0)begin
                        black=1;left=boundary*120;right=left+64;bottom=486;
                    end
                end
            end else if(guitar && px>=32 && py>=536 && py<584)begin
                slot=(px-32)/74;
                if(slot<13 && (px-32)%74<68)begin
                    valid=1;note=slot;left=32+slot*74;right=left+68;top=536;bottom=584;
                end
            end
            if(py>=24 && py<72)begin
                if(px>=760 && px<872)begin kind=1;value=0;end
                if(px>=880 && px<992)begin kind=1;value=1;end
            end
            if(py>=100 && py<140)begin
                if(px>=568 && px<760)begin kind=2;value=(px-568)/64;end
                if(px>=916 && px<992)begin kind=3;value=0;end
            end
            model={valid,black,note,left,right,top,bottom,kind,value};
        end
    endfunction

    initial begin
        passed=0;samples=0;piano_count=0;black_count=0;guitar_count=0;control_count=0;
        x=0;y=0;instrument_guitar=0;
        for(yy=0;yy<4096;yy=yy+1)begin
            for(xx=0;xx<4096;xx=xx+1)begin
                for(mode=0;mode<2;mode=mode+1)begin
                    x=xx;y=yy;instrument_guitar=mode;
                    #1; // 等待所有组合delta收敛；没有时钟可等待，也不允许增加一拍。
                    expected=model(x,y,instrument_guitar);
                    if(actual!==expected)begin
                        $display("FAIL ui map x=%0d y=%0d guitar=%0d expected=%h got=%h",
                                 x,y,instrument_guitar,expected,actual);
                        $stop;
                    end
`ifdef UI_MAP_REFERENCE
                    if(actual!==reference)begin
                        $display("FAIL ui map baseline x=%0d y=%0d guitar=%0d ref=%h got=%h",
                                 x,y,instrument_guitar,reference,actual);
                        $stop;
                    end
`endif
                    samples=samples+1;
                    if(note_valid && !instrument_guitar)piano_count=piano_count+1;
                    if(key_black)black_count=black_count+1;
                    if(note_valid && instrument_guitar)guitar_count=guitar_count+1;
                    if(control_kind!=0)control_count=control_count+1;
                end
            end
        end
        if(samples!=33554432 || piano_count!=203520 || black_count!=37760 ||
           guitar_count!=42432 || control_count!=42944)begin
            $display("FAIL ui map coverage samples=%0d piano=%0d black=%0d guitar=%0d controls=%0d",
                     samples,piano_count,black_count,guitar_count,control_count);
            $stop;
        end
        passed=1;
        $display("PASS tb_ui_map_equivalence exhaustive samples=33554432 piano=203520 black=37760 guitar=42432 controls=42944");
        $finish;
    end
    initial begin
        #40000000;
        $display("FAIL ui map timeout");
        $stop;
    end
endmodule
