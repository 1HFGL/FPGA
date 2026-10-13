`timescale 1ns/1ps

// 同相位读取基波和两组单周期乐器表。选择位与 ROM 同拍保存。
// 基波固定为半幅正弦，亮度只改变附加谐波，不调制基波音高。
module instrument_wave #(
    parameter SINE_ROM_FILE="rtl/rom/sine_1024.mem",
    parameter GUITAR_ROM_FILE="rtl/rom/guitar_1024.mem",
    parameter STRINGS_ROM_FILE="rtl/rom/strings_1024.mem"
) (
    input wire clk, rst, read_en,
    input wire [9:0] addr,
    input wire instrument, harmonics_enable,
    output wire signed [15:0] base_sample, full_sample,
    output wire sample_valid
);
    wire signed [15:0] sine_sample, guitar_sample, strings_sample;
    wire sine_valid, guitar_valid, strings_valid;
    reg selected, allow_harmonics;
    wave_lut #(.ROM_FILE(SINE_ROM_FILE)) u_sine (
        .clk(clk),.rst(rst),.read_en(read_en),.addr(addr),
        .sample(sine_sample),.sample_valid(sine_valid));
    wave_lut #(.ROM_FILE(GUITAR_ROM_FILE)) u_guitar (
        .clk(clk),.rst(rst),.read_en(read_en),.addr(addr),
        .sample(guitar_sample),.sample_valid(guitar_valid));
    wave_lut #(.ROM_FILE(STRINGS_ROM_FILE)) u_strings (
        .clk(clk),.rst(rst),.read_en(read_en),.addr(addr),
        .sample(strings_sample),.sample_valid(strings_valid));
    always @(posedge clk) begin
        if(rst) begin selected<=0; allow_harmonics<=0; end
        else if(read_en) begin selected<=instrument; allow_harmonics<=harmonics_enable; end
    end
    assign base_sample=$signed(sine_sample)>>>1;
    assign full_sample=allow_harmonics?(selected?strings_sample:guitar_sample):base_sample;
    assign sample_valid=sine_valid & guitar_valid & strings_valid;
endmodule
