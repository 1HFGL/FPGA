`timescale 1ns/1ps

// 只存一周期正弦的1024个16位有符号振幅，不存整段声音。
// 输入addr是这一圈的位置；输出sample是该位置的正/负振幅，有一层输出寄存器。
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
        // Gowin将此文件内容用于初始化只读存储器；板上运行不需要连接电脑读文件。
        // 工程仍必须保留ROM_FILE及正确搜索路径，否则重新构建无法得到同一波形。
        $readmemh(ROM_FILE, rom);
    end

    // 上升沿read_en=1时接受地址，沿后sample/sample_valid一起更新。
    // 高有效同步复位优先；空闲时sample保持旧值但valid=0，不能重复当成新样本。
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
