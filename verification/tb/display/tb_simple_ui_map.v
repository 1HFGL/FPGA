`timescale 1ns/1ps
// 独立像素合同：用除法/参考表推导期望，不复用RTL的比较循环。
module tb_simple_ui_map;
    reg [11:0] x=0,y=0;
    reg mode=0;
    wire hit,black;
    wire [3:0] note;
    wire [1:0] kind,value;
    wire [11:0] l,r,t,b;
    instrument_ui_map dut(.x(x),.y(y),.instrument_guitar(mode),.note_valid(hit),
        .key_black(black),.note_index(note),.key_left(l),.key_right(r),.key_top(t),.key_bottom(b),
        .control_kind(kind),.control_value(value));
    integer xx,yy,m,k,w,n,expected,ek,ev,total=0;
    integer whites[0:7];integer boundaries[0:4];integer blacks[0:4];
    initial begin
        whites[0]=0;whites[1]=2;whites[2]=4;whites[3]=5;
        whites[4]=7;whites[5]=9;whites[6]=11;whites[7]=12;
        boundaries[0]=152;boundaries[1]=272;boundaries[2]=512;boundaries[3]=632;boundaries[4]=752;
        blacks[0]=1;blacks[1]=3;blacks[2]=6;blacks[3]=8;blacks[4]=10;
        for(m=0;m<2;m=m+1)begin
            mode=m;
            for(yy=0;yy<600;yy=yy+1)for(xx=0;xx<1024;xx=xx+1)begin
                expected=-1;ek=0;ev=0;
                if(m==0 && yy>=368 && yy<580 && xx>=32 && xx<992)begin
                    w=(xx-32)/120;expected=whites[w];
                    if(yy<486)for(k=0;k<5;k=k+1)
                        if(xx>=boundaries[k]-32 && xx<boundaries[k]+32)expected=blacks[k];
                end
                if(m==1 && yy>=536 && yy<584 && xx>=32 && xx<994)begin
                    n=(xx-32)/74;if(n<=12 && (xx-32)%74<68)expected=n;
                end
                if(yy>=24 && yy<72)begin
                    if(xx>=760 && xx<872)begin ek=1;ev=0;end
                    if(xx>=880 && xx<992)begin ek=1;ev=1;end
                end
                if(yy>=100 && yy<140)begin
                    if(xx>=568 && xx<760)begin ek=2;ev=(xx-568)/64;end
                    if(xx>=916 && xx<992)begin ek=3;ev=0;end
                end
                x=xx;y=yy;#1;
                if(hit!==(expected>=0) || (hit && note!==expected) || kind!==ek || value!==ev)begin
                    $display("FAIL map m=%0d x=%0d y=%0d hit=%0d/%0d note=%0d exp=%0d ctrl=%0d/%0d",m,xx,yy,hit,expected>=0,note,expected,kind,ek);$finish;
                end
                if(hit && !(x>=l && x<r && y>=t && y<b))begin $display("FAIL map rectangle");$finish;end
                total=total+1;
            end
        end
        x=4095;y=4095;#1;if(hit || kind!=0)begin $display("FAIL invalid coordinate");$finish;end
        $display("PASS tb_simple_ui_map: %0d pixels, black precedence, 13 guitar pads, exact control edges, invalid coordinates",total);$finish;
    end
endmodule
