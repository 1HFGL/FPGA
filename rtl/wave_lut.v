`timescale 1ns/1ps

// 1024-point, signed 16-bit sine ROM with a registered output.
module wave_lut #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem"
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               read_en,
    input  wire [9:0]         addr,
    output reg signed [15:0] sample,
    output reg                sample_valid
);
    reg signed [15:0] rom [0:1023];

    initial begin
        $readmemh(ROM_FILE, rom);
    end

    // 输出上升沿接受; 之后输出更新 .
    // Reset wins over read_en. While idle, sample holds and valid becomes 0.
    always @(posedge clk) begin
        if (rst) begin
            sample       <= 16'sd0;
            sample_valid <= 1'b0;
        end
        else begin
            sample_valid <= read_en;
            if (read_en)
                sample <= rom[addr];
        end
    end
endmodule
