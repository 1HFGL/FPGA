`timescale 1ns/1ps

// 两个数学生成的单周期波表：0=柔和正弦，1=含二/三/四次谐波。
// 复用原同步 ROM；两个表同拍读取，选择位也同拍保存，避免读错上一拍音色。
// 无请求时两个 ROM 及选择位都保持，因此 sample 保持、valid 清零。
module wave_lut_timbre #(
    parameter ROM_FILE = "rtl/rom/sine_1024.mem",
    parameter BRIGHT_ROM_FILE = "rtl/rom/bright_1024.mem"
) (
    input wire clk, rst, read_en,
    input wire [9:0] addr,
    input wire timbre, // 必须连接：0 柔和，1 明亮
    output wire signed [15:0] sample,
    output wire sample_valid
);
    wire signed [15:0] soft_sample, bright_sample;
    wire soft_valid, bright_valid;
    reg selected_bright;
    wave_lut #(.ROM_FILE(ROM_FILE)) u_soft (
        .clk(clk), .rst(rst), .read_en(read_en), .addr(addr),
        .sample(soft_sample), .sample_valid(soft_valid)
    );
    wave_lut #(.ROM_FILE(BRIGHT_ROM_FILE)) u_bright (
        .clk(clk), .rst(rst), .read_en(read_en), .addr(addr),
        .sample(bright_sample), .sample_valid(bright_valid)
    );
    always @(posedge clk) begin
        if (rst) selected_bright <= 1'b0;
        else if (read_en) selected_bright <= timbre;
    end
    assign sample = selected_bright ? bright_sample : soft_sample;
    assign sample_valid = soft_valid & bright_valid;
endmodule
