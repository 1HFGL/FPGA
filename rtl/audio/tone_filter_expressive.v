// Two monotone low-pass sections, logarithmic cutoff control, no resonance/gain.
// At 127 both sections are exact bypass. R0 input -> R5 valid -> R6 consume.
// A small combinational coefficient table uses logic, not an audio delay RAM.
module tone_filter_expressive(
    input wire clk,rst_n,in_valid,
    input wire signed [15:0] sample_in,
    input wire [6:0] brightness,
    output wire signed [15:0] sample_out,
    output wire out_valid,tail_active,overrun
);
    wire signed [15:0] first_sample;
    wire first_valid,first_tail,second_tail,first_overrun,second_overrun;
    reg [6:0] captured_brightness;
    // Both poles must use the control sampled with the same input sample.
    // A live slider change during R1..R3 must not split one sample's response.
    always @(posedge clk)begin
        if(!rst_n)captured_brightness<=127;
        else if(in_valid)captured_brightness<=brightness;
    end
    tone_filter #(.PERCEPTUAL_CURVE(1)) u_first(
        .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.sample_in(sample_in),
        .brightness(brightness),.sample_out(first_sample),.out_valid(first_valid),
        .tail_active(first_tail),.overrun(first_overrun));
    tone_filter #(.PERCEPTUAL_CURVE(1)) u_second(
        .clk(clk),.rst_n(rst_n),.in_valid(first_valid),.sample_in(first_sample),
        .brightness(captured_brightness),.sample_out(sample_out),.out_valid(out_valid),
        .tail_active(second_tail),.overrun(second_overrun));
    assign tail_active=first_tail || second_tail;
    assign overrun=first_overrun || second_overrun;
endmodule
