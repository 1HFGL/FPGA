// Atomic targets for future C input or UART. Single 50 MHz clock domain.
// Volume 0..127: 127=unity, otherwise value/128. Bend 0..1024: -2..+2 semitones.
// Target steps do not restart envelopes/phases. Full-range ramps <=128 samples.
module music_controls #(
    parameter RATIO_ROM_FILE="rtl/rom/pitch_bend_1025.mem"
)(
    input wire clk,rst_n,sample_request,control_valid,
    input wire [6:0] control_volume,
    input wire [10:0] control_bend,
    output reg [6:0] target_volume,
    output reg [10:0] target_bend,
    output reg [16:0] gain_q16,
    output reg [10:0] bend_current,
    output reg [16:0] pitch_ratio_q16
);
    // Five hex digits per word; upper three bits are zero padding.
    reg [19:0] ratio_rom[0:1024];
    initial $readmemh(RATIO_ROM_FILE,ratio_rom);
    wire [16:0] target_gain=(target_volume==127)?17'd65536:{1'b0,target_volume,9'd0};
    wire [17:0] gain_up={1'b0,gain_q16}+18'd512;
    wire [17:0] gain_down_limit={1'b0,target_gain}+18'd512;
    wire [11:0] bend_up={1'b0,bend_current}+12'd8;
    wire [11:0] bend_down_limit={1'b0,target_bend}+12'd8;
    always @(posedge clk) begin
        if(!rst_n) begin
            target_volume<=8;target_bend<=512;
            // Start at 8/128 gain immediately, including the first sample after reset.
            gain_q16<=4096;bend_current<=512;pitch_ratio_q16<=65536;
        end else begin
            // Ignore an invalid external packet atomically (UART validates too).
            if(control_valid && control_bend<=1024) begin
                target_volume<=control_volume;target_bend<=control_bend;
            end
            // Synchronous ROM read settles long before the next audio request.
            pitch_ratio_q16<=ratio_rom[bend_current][16:0];
            if(sample_request) begin
                if(gain_q16<target_gain) gain_q16<=(gain_up<target_gain)?gain_up[16:0]:target_gain;
                else if(gain_q16>target_gain) gain_q16<=(gain_q16>gain_down_limit)?gain_q16-17'd512:target_gain;
                if(bend_current<target_bend) bend_current<=(bend_up<target_bend)?bend_up[10:0]:target_bend;
                else if(bend_current>target_bend) bend_current<=(bend_current>bend_down_limit)?bend_current-11'd8:target_bend;
            end
        end
    end
endmodule
