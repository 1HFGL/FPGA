// 48kHz mono feedback delay: 7680 samples = 160ms. Q16.2 delay memory.
// Feedback 3/8, new input 5/8: bounded DC gain, truncation to zero terminates tails.
// R0 accept -> R4 valid -> R5 consume; the direct signal never waits 160ms.
module echo_delay #(
    parameter integer WET_LEVEL=16 // /128: 12.5% delayed, 87.5% direct
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
    function signed [17:0] sat18;
        input signed [31:0] v;
        begin if(v>131071)sat18=18'sh1ffff;else if(v< -131072)sat18=18'sh20000;else sat18=v[17:0];end
    endfunction
    reg signed [17:0] memory[0:7679];
    reg [12:0] pointer,age,nonzero;
    reg [2:0] state;
    reg signed [15:0] dry;
    reg signed [17:0] rd,delayed,write_word;
    reg signed [31:0] weighted;
    reg signed [31:0] mixed;
    // Exact 20*dry + 3*delayed, before the original truncation at state 3.
    // Range [-1048576,1048553] fits 21 signed bits; retain the original 32-bit interface.
    wire signed [31:0] dry_ext={{16{dry[15]}},dry};
    wire signed [31:0] delayed_ext={{14{delayed[17]}},delayed};
    wire signed [31:0] feedback_weighted /* synthesis syn_dspstyle="logic" */;
    assign feedback_weighted=(dry_ext<<<4)+(dry_ext<<<2)+(delayed_ext<<<1)+delayed_ext;
    wire accept=in_valid && !busy;
    assign busy=(state!=0);
    assign tail_active=(nonzero!=0 || sample_out!=0 || (busy && dry!=0));
    always @(posedge clk)begin
        if(rst_n && accept)rd<=memory[pointer];
        if(rst_n && state==4)memory[pointer]<=write_word;
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            pointer<=0;age<=0;nonzero<=0;state<=0;dry<=0;delayed<=0;write_word<=0;
            weighted<=0;mixed<=0;sample_out<=0;out_valid<=0;overrun<=0;
        end else begin
            out_valid<=0;
            if(in_valid && busy)overrun<=1;
            case(state)
                0:if(in_valid)begin dry<=sample_in;state<=1;end
                1:begin delayed<=(age==7680)?rd:18'sd0;state<=2;end
                2:begin
                    weighted<=feedback_weighted;state<=3;
                end
                3:begin
                    write_word<=sat18(trunc0(weighted,3));
                    mixed<=(trunc0({{14{delayed[17]}},delayed},2)-$signed(dry))*WET_LEVEL;state<=4;
                end
                4:begin
                    sample_out<=sat16($signed(dry)+trunc0(mixed,7));out_valid<=1;state<=0;
                    if(delayed==0 && write_word!=0)nonzero<=nonzero+1'b1;
                    else if(delayed!=0 && write_word==0)nonzero<=nonzero-1'b1;
                    if(pointer==7679)pointer<=0;else pointer<=pointer+1'b1;
                    if(age<7680)age<=age+1'b1;
                end
                default:state<=0;
            endcase
        end
    end
    // synthesis translate_off
    initial if(WET_LEVEL<0 || WET_LEVEL>128)begin $display("FAIL echo WET_LEVEL");$finish;end
    // synthesis translate_on
endmodule
