// Two interpolated, independently modulated taps from one 1024-word mono delay.
// 48kHz: tap0 10.67..13.33ms at ~0.60Hz; tap1 16..18.67ms at ~0.83Hz.
// R0 accept -> R11 valid -> R12 consume. Delay time is NOT direct-sound latency.
module chorus_effect #(
    parameter integer WET_LEVEL=24 // /128: 18.75% combined wet, 81.25% direct
)(
    input wire clk,rst_n,in_valid,
    input wire signed [15:0] sample_in,
    output reg signed [15:0] sample_out,
    output reg out_valid,
    output wire tail_active,busy,
    output reg overrun
);
    function signed [31:0] trunc0;
        input signed [31:0] v;input integer shift;
        begin if(v<0)trunc0=-((-v)>>>shift);else trunc0=v>>>shift;end
    endfunction
    function signed [15:0] sat16;
        input signed [31:0] v;
        begin if(v>32767)sat16=16'sh7fff;else if(v< -32768)sat16=16'sh8000;else sat16=v[15:0];end
    endfunction
    reg signed [15:0] memory[0:1023];
    reg [9:0] pointer,a0,a1,a2,a3;
    reg [10:0] age,nonzero;
    reg [31:0] phase0,phase1;
    wire [30:0] triangle0=phase0[31]?~phase0[30:0]:phase0[30:0];
    wire [30:0] triangle1=phase1[31]?~phase1[30:0]:phase1[30:0];
    wire [17:0] delay0=18'd131072+{3'd0,triangle0[30:16]};
    wire [17:0] delay1=18'd196608+{3'd0,triangle1[30:16]};
    reg [7:0] fraction0,fraction1;
    reg [3:0] valid_history,state;
    reg signed [15:0] rd,old,dry,t0a,t0b,t1a,t1b,tap0,tap1,average;
    reg signed [16:0] delta0,delta1;
    reg signed [25:0] product0,product1;
    reg signed [31:0] mixed;
    wire [9:0] address=(state==1)?a0:(state==2)?a1:(state==3)?a2:(state==4)?a3:pointer;
    assign busy=(state!=0);
    assign tail_active=(nonzero!=0 || sample_out!=0 || (busy && dry!=0));
    // One sequentially scheduled read port and one write port, no RAM reset loop.
    always @(posedge clk)begin
        if(rst_n && state>=1 && state<=5)rd<=memory[address];
        if(rst_n && state==10)memory[pointer]<=dry;
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            pointer<=0;age<=0;nonzero<=0;state<=0;
            phase0<=0;phase1<=32'h40000000;
            a0<=0;a1<=0;a2<=0;a3<=0;fraction0<=0;fraction1<=0;valid_history<=0;
            old<=0;dry<=0;t0a<=0;t0b<=0;t1a<=0;t1b<=0;tap0<=0;tap1<=0;average<=0;
            delta0<=0;delta1<=0;product0<=0;product1<=0;mixed<=0;
            sample_out<=0;out_valid<=0;overrun<=0;
        end else begin
            out_valid<=0;
            if(in_valid && busy)overrun<=1;
            case(state)
                0:if(in_valid)begin
                    dry<=sample_in;
                    a0<=pointer-delay0[17:8];a1<=pointer-delay0[17:8]-10'd1;
                    a2<=pointer-delay1[17:8];a3<=pointer-delay1[17:8]-10'd1;
                    fraction0<=delay0[7:0];fraction1<=delay1[7:0];
                    valid_history<={age>=({1'b0,delay1[17:8]}+11'd1),age>={1'b0,delay1[17:8]},
                        age>=({1'b0,delay0[17:8]}+11'd1),age>={1'b0,delay0[17:8]}};
                    phase0<=phase0+32'd53687;phase1<=phase1+32'd74267;state<=1;
                end
                1:state<=2;
                2:begin t0a<=valid_history[0]?rd:16'sd0;state<=3;end
                3:begin t0b<=valid_history[1]?rd:16'sd0;state<=4;end
                4:begin t1a<=valid_history[2]?rd:16'sd0;state<=5;end
                5:begin t1b<=valid_history[3]?rd:16'sd0;state<=6;end
                6:begin
                    old<=(age==1024)?rd:16'sd0;
                    delta0<=$signed({t0b[15],t0b})-$signed({t0a[15],t0a});
                    delta1<=$signed({t1b[15],t1b})-$signed({t1a[15],t1a});state<=7;
                end
                7:begin
                    product0<=delta0*$signed({1'b0,fraction0});
                    product1<=delta1*$signed({1'b0,fraction1});state<=8;
                end
                8:begin
                    tap0<=sat16($signed(t0a)+trunc0({{6{product0[25]}},product0},8));
                    tap1<=sat16($signed(t1a)+trunc0({{6{product1[25]}},product1},8));state<=9;
                end
                9:begin average<=sat16(trunc0($signed(tap0)+$signed(tap1),1));state<=10;end
                10:begin
                    mixed<=($signed(average)-$signed(dry))*WET_LEVEL;
                    if(old==0 && dry!=0)nonzero<=nonzero+1'b1;
                    else if(old!=0 && dry==0)nonzero<=nonzero-1'b1;
                    state<=11;
                end
                11:begin
                    sample_out<=sat16($signed(dry)+trunc0(mixed,7));out_valid<=1;state<=0;
                    pointer<=pointer+10'd1;if(age<1024)age<=age+1'b1;
                end
                default:state<=0;
            endcase
        end
    end
    // synthesis translate_off
    initial if(WET_LEVEL<0 || WET_LEVEL>128)begin $display("FAIL chorus WET_LEVEL");$finish;end
    // synthesis translate_on
endmodule
