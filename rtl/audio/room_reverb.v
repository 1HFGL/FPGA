// 48 kHz mono room: four damped feedback combs and two true allpasses.
// Internal delay words are signed Q16.2 (18 bits); truncation is toward zero.
// Accept only when !busy. R0 accept -> R8 out_valid -> R9 downstream consume.
// No RAM reset loop: fill age masks unread history after EVERY reset.
module room_reverb #(
    parameter integer WET_LEVEL=32 // 0..128; 32 = 25 percent wet, 75 percent dry
)(
    input wire clk,rst_n,in_valid,
    input wire signed [15:0] sample_in,
    output reg signed [15:0] sample_out,
    output reg out_valid,
    output wire tail_active,busy,
    output reg overrun
);
    function signed [31:0] trunc0;
        input signed [31:0] value;
        input integer shift;
        begin
            if(value<0) trunc0=-((-value)>>>shift);
            else trunc0=value>>>shift;
        end
    endfunction
    function signed [17:0] sat18;
        input signed [31:0] value;
        begin
            if(value>131071) sat18=18'sd131071;
            else if(value< -131072) sat18=-18'sd131072;
            else sat18=value[17:0];
        end
    endfunction
    function signed [15:0] sat16;
        input signed [31:0] value;
        begin
            if(value>32767) sat16=16'sd32767;
            else if(value< -32768) sat16=-16'sd32768;
            else sat16=value[15:0];
        end
    endfunction
    reg signed [17:0] mem0[0:1498],mem1[0:1600],mem2[0:1746],mem3[0:1878];
    reg signed [17:0] mem4[0:222],mem5[0:562];
    reg [10:0] p0,p1,p2,p3;
    reg [7:0] p4;
    reg [9:0] p5;
    reg [10:0] age;
    reg [3:0] state;
    wire accept=in_valid && !busy;
    assign busy=(state!=0);
    reg signed [17:0] rd0,rd1,rd2,rd3,rd4,rd5;
    reg signed [17:0] d0,d1,d2,d3,d4,d5;
    reg signed [17:0] lp0,lp1,lp2,lp3,nlp0,nlp1,nlp2,nlp3;
    reg signed [24:0] fb0,fb1,fb2,fb3;
    reg signed [17:0] w0,w1,w2,w3,w4,w5,wet0,ap1,ap2;
    reg signed [31:0] sum,mix_product,feed;
    reg signed [15:0] dry;
    // Count nonzero delay cells, not elapsed time: silent gaps inside a tail
    // must not close PA_EN, and an arbitrary timeout must not chop late energy.
    reg [11:0] nz0,nz1,nz2,nz3,nz4,nz5;
    assign tail_active=(nz0!=0 || nz1!=0 || nz2!=0 || nz3!=0 || nz4!=0 || nz5!=0 ||
        lp0!=0 || lp1!=0 || lp2!=0 || lp3!=0 || sample_out!=0 ||
        (busy && (dry!=0 || wet0!=0 || ap1!=0 || ap2!=0)));
    // Separate clocked RAM ports allow inference of embedded block RAM.
    // Their undefined initial contents never reach arithmetic before age permits.
    always @(posedge clk) begin
        if(rst_n && accept) begin
            rd0<=mem0[p0];rd1<=mem1[p1];rd2<=mem2[p2];rd3<=mem3[p3];
            rd4<=mem4[p4];rd5<=mem5[p5];
        end
        if(rst_n && state==5)begin mem0[p0]<=w0;mem1[p1]<=w1;mem2[p2]<=w2;mem3[p3]<=w3;end
        if(rst_n && state==6)mem4[p4]<=w4;
        if(rst_n && state==7)mem5[p5]<=w5;
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=0;age<=0;p0<=0;p1<=0;p2<=0;p3<=0;p4<=0;p5<=0;
            nz0<=0;nz1<=0;nz2<=0;nz3<=0;nz4<=0;nz5<=0;
            d0<=0;d1<=0;d2<=0;d3<=0;d4<=0;d5<=0;
            lp0<=0;lp1<=0;lp2<=0;lp3<=0;nlp0<=0;nlp1<=0;nlp2<=0;nlp3<=0;
            fb0<=0;fb1<=0;fb2<=0;fb3<=0;
            w0<=0;w1<=0;w2<=0;w3<=0;w4<=0;w5<=0;wet0<=0;ap1<=0;ap2<=0;
            sum<=0;mix_product<=0;feed<=0;dry<=0;sample_out<=0;out_valid<=0;overrun<=0;
        end else begin
            out_valid<=0;
            if(in_valid && busy)overrun<=1;
            case(state)
                0:if(in_valid)begin dry<=sample_in;state<=1;end
                1:begin
                    d0<=(age>=1499)?rd0:18'sd0;d1<=(age>=1601)?rd1:18'sd0;
                    d2<=(age>=1747)?rd2:18'sd0;d3<=(age>=1879)?rd3:18'sd0;
                    d4<=(age>=223)?rd4:18'sd0;d5<=(age>=563)?rd5:18'sd0;
                    // x/8 in Q16.2 equals x/2; widen before arithmetic.
                    feed<=trunc0({{16{dry[15]}},dry},1);state<=2;
                end
                2:begin
                    nlp0<=sat18(trunc0($signed(d0)+$signed(lp0),1));
                    nlp1<=sat18(trunc0($signed(d1)+$signed(lp1),1));
                    nlp2<=sat18(trunc0($signed(d2)+$signed(lp2),1));
                    nlp3<=sat18(trunc0($signed(d3)+$signed(lp3),1));
                    sum<=$signed(d0)+$signed(d1)+$signed(d2)+$signed(d3);state<=3;
                end
                3:begin
                    fb0<=$signed(nlp0)*7'sd52;fb1<=$signed(nlp1)*7'sd51;
                    fb2<=$signed(nlp2)*7'sd50;fb3<=$signed(nlp3)*7'sd49;
                    lp0<=nlp0;lp1<=nlp1;lp2<=nlp2;lp3<=nlp3;
                    wet0<=sat18(sum);state<=4;
                end
                4:begin
                    w0<=sat18(feed+trunc0({{7{fb0[24]}},fb0},6));
                    w1<=sat18(feed+trunc0({{7{fb1[24]}},fb1},6));
                    w2<=sat18(feed+trunc0({{7{fb2[24]}},fb2},6));
                    w3<=sat18(feed+trunc0({{7{fb3[24]}},fb3},6));
                    ap1<=sat18($signed(d4)-trunc0({{14{wet0[17]}},wet0},1));state<=5;
                end
                5:begin
                    if(d0==0 && w0!=0)nz0<=nz0+1'b1;else if(d0!=0 && w0==0)nz0<=nz0-1'b1;
                    if(d1==0 && w1!=0)nz1<=nz1+1'b1;else if(d1!=0 && w1==0)nz1<=nz1-1'b1;
                    if(d2==0 && w2!=0)nz2<=nz2+1'b1;else if(d2!=0 && w2==0)nz2<=nz2-1'b1;
                    if(d3==0 && w3!=0)nz3<=nz3+1'b1;else if(d3!=0 && w3==0)nz3<=nz3-1'b1;
                    w4<=sat18($signed(wet0)+trunc0({{14{ap1[17]}},ap1},1));
                    ap2<=sat18($signed(d5)-trunc0({{14{ap1[17]}},ap1},1));state<=6;
                end
                6:begin
                    if(d4==0 && w4!=0)nz4<=nz4+1'b1;else if(d4!=0 && w4==0)nz4<=nz4-1'b1;
                    w5<=sat18($signed(ap1)+trunc0({{14{ap2[17]}},ap2},1));state<=7;
                end
                7:begin
                    if(d5==0 && w5!=0)nz5<=nz5+1'b1;else if(d5!=0 && w5==0)nz5<=nz5-1'b1;
                    mix_product<=(trunc0({{14{ap2[17]}},ap2},2)-$signed(dry))*WET_LEVEL;state<=8;
                end
                8:begin
                    sample_out<=sat16($signed(dry)+trunc0(mix_product,7));out_valid<=1;state<=0;
                    if(p0==1498)p0<=0;else p0<=p0+1'b1;
                    if(p1==1600)p1<=0;else p1<=p1+1'b1;
                    if(p2==1746)p2<=0;else p2<=p2+1'b1;
                    if(p3==1878)p3<=0;else p3<=p3+1'b1;
                    if(p4==222)p4<=0;else p4<=p4+1'b1;
                    if(p5==562)p5<=0;else p5<=p5+1'b1;
                    if(age<1879)age<=age+1'b1;
                end
                default:state<=0;
            endcase
        end
    end
    // synthesis translate_off
    initial begin
        if(WET_LEVEL<0 || WET_LEVEL>128)begin $display("FAIL room WET_LEVEL outside 0..128");$finish;end
    end
    // synthesis translate_on
endmodule
