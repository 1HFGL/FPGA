// 全局旋钮参数：50MHz同域；每个音频请求推进一次有界平滑。
// 参数有效时成对锁存；ADC故障保留最后有效值，复位为单位音量/原音高。
// Q1.16增益0..65536；Q2.16频率比，半音比为2^(1/12)，63/64中心死区。
module piano_controls(
    input wire clk,rst_n,sample_request,
    input wire [13:0] knob_value_flat,
    input wire knob_valid,param_ready,param_fault,
    output reg [16:0] master_gain,
    output reg [17:0] bend_ratio
);
    reg [16:0] gain_target;
    reg [17:0] bend_target;
    wire [22:0] gain_product=knob_value_flat[6:0]*17'd65536;
    wire [23:0] gain_quotient=({1'b0,gain_product}+24'd63)/24'd127;
    wire [16:0] mapped_gain=gain_quotient[16:0]; // 范围已证明0..65536，显式截位
    function [17:0] ratio_for_knob;
        input [6:0] value;
        begin
            // 生成依据：round(65536*2^(cents/1200))；不是音频录音或PCM。
            case(value)
                7'd0: ratio_for_knob=18'd58386;
                7'd1: ratio_for_knob=18'd58493;
                7'd2: ratio_for_knob=18'd58600;
                7'd3: ratio_for_knob=18'd58708;
                7'd4: ratio_for_knob=18'd58816;
                7'd5: ratio_for_knob=18'd58924;
                7'd6: ratio_for_knob=18'd59032;
                7'd7: ratio_for_knob=18'd59140;
                7'd8: ratio_for_knob=18'd59249;
                7'd9: ratio_for_knob=18'd59358;
                7'd10: ratio_for_knob=18'd59466;
                7'd11: ratio_for_knob=18'd59576;
                7'd12: ratio_for_knob=18'd59685;
                7'd13: ratio_for_knob=18'd59794;
                7'd14: ratio_for_knob=18'd59904;
                7'd15: ratio_for_knob=18'd60014;
                7'd16: ratio_for_knob=18'd60124;
                7'd17: ratio_for_knob=18'd60235;
                7'd18: ratio_for_knob=18'd60345;
                7'd19: ratio_for_knob=18'd60456;
                7'd20: ratio_for_knob=18'd60567;
                7'd21: ratio_for_knob=18'd60678;
                7'd22: ratio_for_knob=18'd60789;
                7'd23: ratio_for_knob=18'd60901;
                7'd24: ratio_for_knob=18'd61013;
                7'd25: ratio_for_knob=18'd61125;
                7'd26: ratio_for_knob=18'd61237;
                7'd27: ratio_for_knob=18'd61349;
                7'd28: ratio_for_knob=18'd61462;
                7'd29: ratio_for_knob=18'd61575;
                7'd30: ratio_for_knob=18'd61688;
                7'd31: ratio_for_knob=18'd61801;
                7'd32: ratio_for_knob=18'd61914;
                7'd33: ratio_for_knob=18'd62028;
                7'd34: ratio_for_knob=18'd62142;
                7'd35: ratio_for_knob=18'd62256;
                7'd36: ratio_for_knob=18'd62370;
                7'd37: ratio_for_knob=18'd62485;
                7'd38: ratio_for_knob=18'd62599;
                7'd39: ratio_for_knob=18'd62714;
                7'd40: ratio_for_knob=18'd62829;
                7'd41: ratio_for_knob=18'd62945;
                7'd42: ratio_for_knob=18'd63060;
                7'd43: ratio_for_knob=18'd63176;
                7'd44: ratio_for_knob=18'd63292;
                7'd45: ratio_for_knob=18'd63408;
                7'd46: ratio_for_knob=18'd63525;
                7'd47: ratio_for_knob=18'd63641;
                7'd48: ratio_for_knob=18'd63758;
                7'd49: ratio_for_knob=18'd63875;
                7'd50: ratio_for_knob=18'd63992;
                7'd51: ratio_for_knob=18'd64110;
                7'd52: ratio_for_knob=18'd64227;
                7'd53: ratio_for_knob=18'd64345;
                7'd54: ratio_for_knob=18'd64463;
                7'd55: ratio_for_knob=18'd64582;
                7'd56: ratio_for_knob=18'd64700;
                7'd57: ratio_for_knob=18'd64819;
                7'd58: ratio_for_knob=18'd64938;
                7'd59: ratio_for_knob=18'd65057;
                7'd60: ratio_for_knob=18'd65176;
                7'd61: ratio_for_knob=18'd65296;
                7'd62: ratio_for_knob=18'd65416;
                7'd63: ratio_for_knob=18'd65536;
                7'd64: ratio_for_knob=18'd65536;
                7'd65: ratio_for_knob=18'd65656;
                7'd66: ratio_for_knob=18'd65777;
                7'd67: ratio_for_knob=18'd65898;
                7'd68: ratio_for_knob=18'd66018;
                7'd69: ratio_for_knob=18'd66140;
                7'd70: ratio_for_knob=18'd66261;
                7'd71: ratio_for_knob=18'd66383;
                7'd72: ratio_for_knob=18'd66504;
                7'd73: ratio_for_knob=18'd66627;
                7'd74: ratio_for_knob=18'd66749;
                7'd75: ratio_for_knob=18'd66871;
                7'd76: ratio_for_knob=18'd66994;
                7'd77: ratio_for_knob=18'd67117;
                7'd78: ratio_for_knob=18'd67240;
                7'd79: ratio_for_knob=18'd67364;
                7'd80: ratio_for_knob=18'd67487;
                7'd81: ratio_for_knob=18'd67611;
                7'd82: ratio_for_knob=18'd67735;
                7'd83: ratio_for_knob=18'd67860;
                7'd84: ratio_for_knob=18'd67984;
                7'd85: ratio_for_knob=18'd68109;
                7'd86: ratio_for_knob=18'd68234;
                7'd87: ratio_for_knob=18'd68359;
                7'd88: ratio_for_knob=18'd68485;
                7'd89: ratio_for_knob=18'd68610;
                7'd90: ratio_for_knob=18'd68736;
                7'd91: ratio_for_knob=18'd68862;
                7'd92: ratio_for_knob=18'd68989;
                7'd93: ratio_for_knob=18'd69115;
                7'd94: ratio_for_knob=18'd69242;
                7'd95: ratio_for_knob=18'd69369;
                7'd96: ratio_for_knob=18'd69497;
                7'd97: ratio_for_knob=18'd69624;
                7'd98: ratio_for_knob=18'd69752;
                7'd99: ratio_for_knob=18'd69880;
                7'd100: ratio_for_knob=18'd70008;
                7'd101: ratio_for_knob=18'd70137;
                7'd102: ratio_for_knob=18'd70266;
                7'd103: ratio_for_knob=18'd70394;
                7'd104: ratio_for_knob=18'd70524;
                7'd105: ratio_for_knob=18'd70653;
                7'd106: ratio_for_knob=18'd70783;
                7'd107: ratio_for_knob=18'd70913;
                7'd108: ratio_for_knob=18'd71043;
                7'd109: ratio_for_knob=18'd71173;
                7'd110: ratio_for_knob=18'd71304;
                7'd111: ratio_for_knob=18'd71435;
                7'd112: ratio_for_knob=18'd71566;
                7'd113: ratio_for_knob=18'd71697;
                7'd114: ratio_for_knob=18'd71829;
                7'd115: ratio_for_knob=18'd71961;
                7'd116: ratio_for_knob=18'd72093;
                7'd117: ratio_for_knob=18'd72225;
                7'd118: ratio_for_knob=18'd72358;
                7'd119: ratio_for_knob=18'd72490;
                7'd120: ratio_for_knob=18'd72623;
                7'd121: ratio_for_knob=18'd72757;
                7'd122: ratio_for_knob=18'd72890;
                7'd123: ratio_for_knob=18'd73024;
                7'd124: ratio_for_knob=18'd73158;
                7'd125: ratio_for_knob=18'd73292;
                7'd126: ratio_for_knob=18'd73427;
                7'd127: ratio_for_knob=18'd73562;
                default: ratio_for_knob=18'd65536;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            gain_target<=17'd65536; bend_target<=18'd65536;
            master_gain<=17'd65536; bend_ratio<=18'd65536;
        end else begin
            if(knob_valid && param_ready && !param_fault) begin
                gain_target<=mapped_gain;
                bend_target<=ratio_for_knob(knob_value_flat[13:7]);
            end
            if(sample_request) begin
                if(master_gain<gain_target)
                    master_gain<=((gain_target-master_gain)>17'd1024)?master_gain+17'd1024:gain_target;
                else if(master_gain>gain_target)
                    master_gain<=((master_gain-gain_target)>17'd1024)?master_gain-17'd1024:gain_target;
                if(bend_ratio<bend_target)
                    bend_ratio<=((bend_target-bend_ratio)>18'd256)?bend_ratio+18'd256:bend_target;
                else if(bend_ratio>bend_target)
                    bend_ratio<=((bend_ratio-bend_target)>18'd256)?bend_ratio-18'd256:bend_target;
            end
        end
    end
endmodule
