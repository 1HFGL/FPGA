// Continuous brightness: one-pole low-pass, y += alpha*(x-y), state Q16.16.
// At 48kHz alpha=2048/65536 gives about 243Hz; brightness=127 is exact bypass.
// Intermediate alpha=(2048+500*brightness)/65536. Positive alpha<=1 is stable.
// Three-stage feedback datapath: accepts samples at least 3 system clocks apart.
// Input at R0 -> product R1 -> output R2 -> downstream consumes R3.
// This shapes musical harmonics; it cannot remove noise added after the DAC.
module tone_filter(
    input wire clk,rst_n,in_valid,
    input wire signed [15:0] sample_in,
    input wire [6:0] brightness,
    output reg signed [15:0] sample_out,
    output reg out_valid,
    output wire tail_active,
    output reg overrun
);
    reg [1:0] stage;
    reg signed [31:0] state_q16;
    reg signed [32:0] delta;
    reg signed [17:0] alpha;
    reg signed [50:0] product;
    reg input_zero;
    wire [22:0] alpha_scaled=brightness*16'd500;
    wire [16:0] alpha_value=(brightness==127)?17'd65536:17'd2048+alpha_scaled[16:0];
    wire signed [31:0] x_q16=$signed({sample_in,16'd0});
    // Round both signs to nearest, ties away from zero; no negative DC bias.
    wire signed [50:0] rounded_product=product+((product<0)?51'sd32767:51'sd32768);
    wire signed [50:0] increment=rounded_product>>>16;
    wire signed [32:0] updated=$signed({state_q16[31],state_q16})+$signed(increment[32:0]);
    // On zero input, stop below half an output LSB to avoid a numerical limit cycle.
    wire flush_zero=input_zero && updated<33'sd32768 && updated> -33'sd32768;
    wire signed [32:0] next_state=flush_zero?33'sd0:updated;
    wire signed [32:0] rounded_output=next_state+((next_state<0)?33'sd32767:33'sd32768);
    wire signed [32:0] output_wide=rounded_output>>>16;
    assign tail_active=(state_q16!=0) || (sample_out!=0);
    always @(posedge clk) begin
        if(!rst_n) begin
            stage<=0;state_q16<=0;delta<=0;alpha<=18'sd65536;product<=0;
            input_zero<=1;sample_out<=0;out_valid<=0;overrun<=0;
        end else begin
            out_valid<=0;
            if(in_valid && stage!=0)overrun<=1;
            case(stage)
                0: if(in_valid) begin
                    delta<=$signed({x_q16[31],x_q16})-$signed({state_q16[31],state_q16});
                    alpha<=$signed({1'b0,alpha_value});input_zero<=(sample_in==0);stage<=1;
                end
                1: begin product<=delta*alpha;stage<=2;end
                2: begin
                    state_q16<=next_state[31:0];
                    if(output_wide>32767)sample_out<=16'sh7fff;
                    else if(output_wide< -32768)sample_out<=16'sh8000;
                    else sample_out<=output_wide[15:0];
                    out_valid<=1;stage<=0;
                end
                default:stage<=0;
            endcase
        end
    end
endmodule
