// 像素域的轻量反馈：只在帧提交沿更新，不参与音频服务。
// activity是按下/松开后的7帧残影强度，held仍是唯一持键判据。
module display_feedback(
    input wire pixel_clk,rst_n,frame_commit,
    input wire [12:0] held,
    input wire instrument_guitar,
    input wire [15:0] raw_peak,
    output reg [38:0] activity,
    output reg [15:0] meter_level,meter_peak,
    output reg [7:0] meter_height,meter_peak_height
);
    reg [12:0] previous;
    reg previous_mode;
    reg [3:0] peak_hold;
    integer k;
    wire [15:0] next_level=(raw_peak>=meter_level)?raw_peak:
        ((meter_level-raw_peak>16'd1024)?meter_level-16'd1024:raw_peak);
    wire [15:0] next_peak=(raw_peak>=meter_peak)?raw_peak:
        ((peak_hold!=0)?meter_peak:((meter_peak-raw_peak>16'd512)?meter_peak-16'd512:raw_peak));
    // Fixed piecewise-log scale, independent of waveform auto gain. Each doubling
    // above 32 PCM codes adds 12 pixels; 32768 is full-scale (128 pixels).
    // Register the mapping once per frame, outside the per-pixel render path.
    function [7:0] scale_peak;
        input [15:0] value;
        reg [7:0] base;
        reg [3:0] fraction;
        reg [5:0] fraction3;
        begin
            base=0;fraction=0;fraction3=0;
            if(value>=16'd32768)scale_peak=8'd128;
            else if(value<16'd32)scale_peak={5'd0,value[4:2]};
            else begin
                casez(value[14:5])
                    10'b1?????????:begin base=116;fraction=value[13:10];end
                    10'b01????????:begin base=104;fraction=value[12:9];end
                    10'b001???????:begin base=92;fraction=value[11:8];end
                    10'b0001??????:begin base=80;fraction=value[10:7];end
                    10'b00001?????:begin base=68;fraction=value[9:6];end
                    10'b000001????:begin base=56;fraction=value[8:5];end
                    10'b0000001???:begin base=44;fraction=value[7:4];end
                    10'b00000001??:begin base=32;fraction=value[6:3];end
                    10'b000000001?:begin base=20;fraction=value[5:2];end
                    default:begin base=8;fraction=value[4:1];end
                endcase
                fraction3={2'd0,fraction}+{1'd0,fraction,1'b0};
                scale_peak=base+{4'd0,fraction3[5:2]};
            end
        end
    endfunction
    always @(posedge pixel_clk or negedge rst_n)begin
        if(!rst_n)begin
            activity<=0;meter_level<=0;meter_peak<=0;previous<=0;previous_mode<=0;peak_hold<=0;
            meter_height<=0;meter_peak_height<=0;
        end else if(frame_commit)begin
            previous<=held;previous_mode<=instrument_guitar;
            for(k=0;k<13;k=k+1)begin
                if(previous_mode!=instrument_guitar)activity[k*3+:3]<=held[k]?3'd7:3'd0;
                else if(held[k]!=previous[k])activity[k*3+:3]<=3'd7;
                else if(activity[k*3+:3]!=0)activity[k*3+:3]<=activity[k*3+:3]-1'b1;
            end
            // 上升即刻跟随；下降每帧最多1024码，约0.53秒从满幅归零。
            meter_level<=next_level;
            meter_height<=scale_peak(next_level);
            meter_peak_height<=scale_peak(next_peak);
            if(raw_peak>=meter_peak)begin meter_peak<=raw_peak;peak_hold<=12;end
            else if(peak_hold!=0)peak_hold<=peak_hold-1'b1;
            else if(meter_peak-raw_peak>16'd512)meter_peak<=meter_peak-16'd512;
            else meter_peak<=raw_peak;
        end
    end
endmodule
