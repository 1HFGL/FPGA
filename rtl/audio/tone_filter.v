// Continuous brightness: one-pole low-pass, y += alpha*(x-y), state Q16.16.
// At 48kHz alpha=2048/65536 gives about 243Hz; brightness=127 is exact bypass.
// Intermediate alpha=(2048+500*brightness)/65536. Positive alpha<=1 is stable.
// Three-stage feedback datapath: accepts samples at least 3 system clocks apart.
// Input at R0 -> product R1 -> output R2 -> downstream consumes R3.
// This shapes musical harmonics; it cannot remove noise added after the DAC.
module tone_filter #(
    parameter integer PERCEPTUAL_CURVE=0 // Legacy response is the compatibility default.
)(
    input wire clk,rst_n,in_valid,
    input wire signed [15:0] sample_in,
    input wire [6:0] brightness,
    output reg signed [15:0] sample_out,
    output reg out_valid,
    output wire tail_active,
    output reg overrun
) /* synthesis syn_romstyle = "logic" */;
    // 系数表仅128×17位，局部使用逻辑实现，避免两级滤波各占一块BSRAM。
    // 仅限制硬件映射，不改变Q16系数、输入快照或R0→R2流水线。
    reg [1:0] stage;
    reg signed [31:0] state_q16;
    reg signed [32:0] delta;
    reg signed [17:0] alpha;
    reg signed [50:0] product;
    reg input_zero;
    wire [22:0] alpha_scaled=brightness*16'd500;
    // BEGIN GENERATED BRIGHTNESS CURVE (model/brightness_response.py)
    function [16:0] perceptual_alpha;
        input [6:0] value;
        begin case(value)
            7'd0: perceptual_alpha=17'd3342;
            7'd1: perceptual_alpha=17'd3431;
            7'd2: perceptual_alpha=17'd3523;
            7'd3: perceptual_alpha=17'd3616;
            7'd4: perceptual_alpha=17'd3712;
            7'd5: perceptual_alpha=17'd3811;
            7'd6: perceptual_alpha=17'd3912;
            7'd7: perceptual_alpha=17'd4015;
            7'd8: perceptual_alpha=17'd4122;
            7'd9: perceptual_alpha=17'd4231;
            7'd10: perceptual_alpha=17'd4342;
            7'd11: perceptual_alpha=17'd4457;
            7'd12: perceptual_alpha=17'd4575;
            7'd13: perceptual_alpha=17'd4695;
            7'd14: perceptual_alpha=17'd4819;
            7'd15: perceptual_alpha=17'd4945;
            7'd16: perceptual_alpha=17'd5075;
            7'd17: perceptual_alpha=17'd5208;
            7'd18: perceptual_alpha=17'd5344;
            7'd19: perceptual_alpha=17'd5484;
            7'd20: perceptual_alpha=17'd5627;
            7'd21: perceptual_alpha=17'd5774;
            7'd22: perceptual_alpha=17'd5924;
            7'd23: perceptual_alpha=17'd6079;
            7'd24: perceptual_alpha=17'd6236;
            7'd25: perceptual_alpha=17'd6398;
            7'd26: perceptual_alpha=17'd6564;
            7'd27: perceptual_alpha=17'd6734;
            7'd28: perceptual_alpha=17'd6907;
            7'd29: perceptual_alpha=17'd7085;
            7'd30: perceptual_alpha=17'd7268;
            7'd31: perceptual_alpha=17'd7454;
            7'd32: perceptual_alpha=17'd7645;
            7'd33: perceptual_alpha=17'd7841;
            7'd34: perceptual_alpha=17'd8041;
            7'd35: perceptual_alpha=17'd8246;
            7'd36: perceptual_alpha=17'd8456;
            7'd37: perceptual_alpha=17'd8671;
            7'd38: perceptual_alpha=17'd8890;
            7'd39: perceptual_alpha=17'd9115;
            7'd40: perceptual_alpha=17'd9345;
            7'd41: perceptual_alpha=17'd9580;
            7'd42: perceptual_alpha=17'd9820;
            7'd43: perceptual_alpha=17'd10066;
            7'd44: perceptual_alpha=17'd10317;
            7'd45: perceptual_alpha=17'd10574;
            7'd46: perceptual_alpha=17'd10837;
            7'd47: perceptual_alpha=17'd11105;
            7'd48: perceptual_alpha=17'd11379;
            7'd49: perceptual_alpha=17'd11659;
            7'd50: perceptual_alpha=17'd11945;
            7'd51: perceptual_alpha=17'd12238;
            7'd52: perceptual_alpha=17'd12536;
            7'd53: perceptual_alpha=17'd12841;
            7'd54: perceptual_alpha=17'd13152;
            7'd55: perceptual_alpha=17'd13469;
            7'd56: perceptual_alpha=17'd13793;
            7'd57: perceptual_alpha=17'd14123;
            7'd58: perceptual_alpha=17'd14460;
            7'd59: perceptual_alpha=17'd14803;
            7'd60: perceptual_alpha=17'd15153;
            7'd61: perceptual_alpha=17'd15510;
            7'd62: perceptual_alpha=17'd15874;
            7'd63: perceptual_alpha=17'd16244;
            7'd64: perceptual_alpha=17'd16621;
            7'd65: perceptual_alpha=17'd17006;
            7'd66: perceptual_alpha=17'd17397;
            7'd67: perceptual_alpha=17'd17795;
            7'd68: perceptual_alpha=17'd18200;
            7'd69: perceptual_alpha=17'd18611;
            7'd70: perceptual_alpha=17'd19030;
            7'd71: perceptual_alpha=17'd19456;
            7'd72: perceptual_alpha=17'd19888;
            7'd73: perceptual_alpha=17'd20328;
            7'd74: perceptual_alpha=17'd20774;
            7'd75: perceptual_alpha=17'd21226;
            7'd76: perceptual_alpha=17'd21686;
            7'd77: perceptual_alpha=17'd22152;
            7'd78: perceptual_alpha=17'd22625;
            7'd79: perceptual_alpha=17'd23104;
            7'd80: perceptual_alpha=17'd23589;
            7'd81: perceptual_alpha=17'd24081;
            7'd82: perceptual_alpha=17'd24578;
            7'd83: perceptual_alpha=17'd25082;
            7'd84: perceptual_alpha=17'd25591;
            7'd85: perceptual_alpha=17'd26106;
            7'd86: perceptual_alpha=17'd26626;
            7'd87: perceptual_alpha=17'd27151;
            7'd88: perceptual_alpha=17'd27681;
            7'd89: perceptual_alpha=17'd28216;
            7'd90: perceptual_alpha=17'd28756;
            7'd91: perceptual_alpha=17'd29299;
            7'd92: perceptual_alpha=17'd29847;
            7'd93: perceptual_alpha=17'd30398;
            7'd94: perceptual_alpha=17'd30952;
            7'd95: perceptual_alpha=17'd31510;
            7'd96: perceptual_alpha=17'd32070;
            7'd97: perceptual_alpha=17'd32632;
            7'd98: perceptual_alpha=17'd33196;
            7'd99: perceptual_alpha=17'd33762;
            7'd100: perceptual_alpha=17'd34329;
            7'd101: perceptual_alpha=17'd34896;
            7'd102: perceptual_alpha=17'd35464;
            7'd103: perceptual_alpha=17'd36032;
            7'd104: perceptual_alpha=17'd36599;
            7'd105: perceptual_alpha=17'd37166;
            7'd106: perceptual_alpha=17'd37730;
            7'd107: perceptual_alpha=17'd38293;
            7'd108: perceptual_alpha=17'd38853;
            7'd109: perceptual_alpha=17'd39411;
            7'd110: perceptual_alpha=17'd39965;
            7'd111: perceptual_alpha=17'd40515;
            7'd112: perceptual_alpha=17'd41061;
            7'd113: perceptual_alpha=17'd41602;
            7'd114: perceptual_alpha=17'd42137;
            7'd115: perceptual_alpha=17'd42667;
            7'd116: perceptual_alpha=17'd43190;
            7'd117: perceptual_alpha=17'd43707;
            7'd118: perceptual_alpha=17'd44216;
            7'd119: perceptual_alpha=17'd44718;
            7'd120: perceptual_alpha=17'd45211;
            7'd121: perceptual_alpha=17'd45696;
            7'd122: perceptual_alpha=17'd46172;
            7'd123: perceptual_alpha=17'd46638;
            7'd124: perceptual_alpha=17'd47094;
            7'd125: perceptual_alpha=17'd47540;
            7'd126: perceptual_alpha=17'd47976;
            7'd127: perceptual_alpha=17'd65536;
            default: perceptual_alpha=17'd65536;
        endcase end
    endfunction
    // END GENERATED BRIGHTNESS CURVE
    wire [16:0] alpha_value=PERCEPTUAL_CURVE ? perceptual_alpha(brightness) :
        ((brightness==127)?17'd65536:17'd2048+alpha_scaled[16:0]);
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
