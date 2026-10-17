// 像素域的轻量反馈：只在帧提交沿更新，不参与音频服务。
// activity是按下/松开后的7帧残影强度，held仍是唯一持键判据。
module display_feedback(
    input wire pixel_clk,rst_n,frame_commit,
    input wire [12:0] held,
    input wire instrument_guitar,
    input wire [15:0] raw_peak,
    output reg [38:0] activity,
    output reg [15:0] meter_level,meter_peak
);
    reg [12:0] previous;
    reg previous_mode;
    reg [3:0] peak_hold;
    integer k;
    always @(posedge pixel_clk or negedge rst_n)begin
        if(!rst_n)begin
            activity<=0;meter_level<=0;meter_peak<=0;previous<=0;previous_mode<=0;peak_hold<=0;
        end else if(frame_commit)begin
            previous<=held;previous_mode<=instrument_guitar;
            for(k=0;k<13;k=k+1)begin
                if(previous_mode!=instrument_guitar)activity[k*3+:3]<=held[k]?3'd7:3'd0;
                else if(held[k]!=previous[k])activity[k*3+:3]<=3'd7;
                else if(activity[k*3+:3]!=0)activity[k*3+:3]<=activity[k*3+:3]-1'b1;
            end
            // 上升即刻跟随；下降每帧最多1024码，约0.53秒从满幅归零。
            if(raw_peak>=meter_level)meter_level<=raw_peak;
            else if(meter_level-raw_peak>16'd1024)meter_level<=meter_level-16'd1024;
            else meter_level<=raw_peak;
            if(raw_peak>=meter_peak)begin meter_peak<=raw_peak;peak_hold<=12;end
            else if(peak_hold!=0)peak_hold<=peak_hold-1'b1;
            else if(meter_peak-raw_peak>16'd512)meter_peak<=meter_peak-16'd512;
            else meter_peak<=raw_peak;
        end
    end
endmodule
