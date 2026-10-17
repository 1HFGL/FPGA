"""离线生成固定中文界面的24x24点阵Verilog；最终FPGA不依赖Python/字体文件。"""
import argparse
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

CHARACTERS = "电子钢琴吉他音量弯低中高区延开关实时波形1234567089半"
EXTENDED_CHARACTERS = "静奏拨弦指位示意输出平倍率复声部就绪CDEFGABx"
assert len(CHARACTERS + EXTENDED_CHARACTERS) <= 63
parser = argparse.ArgumentParser()
parser.add_argument("font", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--digits-font", type=Path, help="可选：数字使用独立等宽字体，需保留许可")
parser.add_argument("--reference", type=Path, help="可选：64个原始24x24字形，供独立位寻址测试")
parser.add_argument("--extended-reference", type=Path, help="64个扩展字形，原参考仍保持32槽兼容")
args = parser.parse_args()
font = ImageFont.truetype(str(args.font), size=24)
font.set_variation_by_axes([500])  # Noto Sans SC 可变字重：medium
digit_font = ImageFont.truetype(str(args.digits_font), size=24) if args.digits_font else font
lines = [
    "// 中文24x24固定点阵；由 verification/scripts/generate_display_font.py 生成，不要手改字形。",
    "// 字形源：Noto Sans SC；Copyright 2014-2021 Adobe；SIL OFL 1.1。",
    "// 许可及来源：docs/display-font/OFL.txt、README.md。",
    "// font_sha256=" + hashlib.sha256(args.font.read_bytes()).hexdigest(),
    "// digits_font_sha256=" + hashlib.sha256((args.digits_font or args.font).read_bytes()).hexdigest(),
    "// 数字可来自Red Hat Mono；Copyright 2024 The Red Hat Project Authors；SIL OFL 1.1。",
    "module display_font24 #(parameter integer SYNCHRONOUS=0, EXTENDED=0) (",
    "    input wire pixel_clk, // 同步模式使用；组合检查入口可接0",
    "    input wire [5:0] glyph_id,",
    "    input wire [4:0] column, row,",
    "    output wire ink",
    ");",
    "    // 先按字符/行选24位，再按列选1位，避免576位大字形后的长可变位选择。",
    "    function [23:0] row_lookup;",
    "        input [10:0] address;",
    "        begin",
    "        case (address)",
]
reference = [0] * 64
for index, char in enumerate(CHARACTERS + EXTENDED_CHARACTERS, 1):
    canvas = Image.new("L", (24, 24), 0)
    active_font = digit_font if char.isascii() else font
    box = active_font.getbbox(char)
    ox = (24 - (box[2] - box[0])) // 2 - box[0]
    oy = (24 - (box[3] - box[1])) // 2 - box[1]
    ImageDraw.Draw(canvas).text((ox, oy), char, fill=255, font=active_font)
    bits = "".join("1" if canvas.getpixel((x, y)) >= 96 else "0" for y in range(24) for x in range(24))
    reference[index] = int(bits, 2)
    for row in range(24):
        row_bits = int(bits[row * 24:(row + 1) * 24], 2)
        if row_bits:
            lines.append(f"            11'd{index * 32 + row}: row_lookup=24'h{row_bits:06x}; // {char} 第{row}行")
lines.extend([
    "            default: row_lookup=24'd0;",
    "        endcase",
    "        end",
    "    endfunction",
    "    generate if(SYNCHRONOUS) begin:g_rom",
    "        // 固定初始化内容由综合工具写入片内ROM；不清零ROM输出，以保留BSRAM推断。",
    "        localparam integer DEPTH=EXTENDED?2048:1024;",
    "        reg [23:0] rows [0:DEPTH-1];",
    "        reg [23:0] row_q;",
    "        reg [4:0] column_q;",
    "        reg invalid_q;",
    "        integer init_index;",
    "        // 分成两个1024次循环，遵守Gowin默认2000次展开限制。",
    "        initial begin",
    "            for(init_index=0;init_index<1024;init_index=init_index+1)",
    "                rows[init_index]=row_lookup(init_index[10:0]);",
    "            if(EXTENDED) for(init_index=1024;init_index<2048;init_index=init_index+1)",
    "                rows[init_index]=row_lookup(init_index[10:0]);",
    "        end",
    "        always @(posedge pixel_clk) begin",
    "            row_q<=rows[EXTENDED?{glyph_id,row}:{1'b0,glyph_id[4:0],row}];",
    "            column_q<=column; invalid_q<=!EXTENDED && glyph_id[5];",
    "        end",
    "        wire [4:0] bit_index=5'd23-column_q;",
    "        assign ink=(!invalid_q && column_q<24) ? row_q[bit_index] : 1'b0;",
    "    end else begin:g_comb",
    "        // 供无时钟的字形/绘制器单元检查；生产显示核心使用上面的一拍ROM。",
    "        wire [23:0] glyph_row=row_lookup({glyph_id,row});",
    "        wire [4:0] bit_index=5'd23-column;",
    "        assign ink=(column<24 && (EXTENDED || !glyph_id[5])) ? glyph_row[bit_index] : 1'b0;",
    "    end endgenerate",
    "endmodule",
])
args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
if args.reference:
    args.reference.parent.mkdir(parents=True, exist_ok=True)
    args.reference.write_text("\n".join(f"{value:0144x}" for value in reference[:32]+[0]*32) + "\n", encoding="ascii")
if args.extended_reference:
    args.extended_reference.parent.mkdir(parents=True, exist_ok=True)
    args.extended_reference.write_text("\n".join(f"{value:0144x}" for value in reference)+"\n",encoding="ascii")
print(f"Generated glyphs; legacy: {CHARACTERS}; extended: {EXTENDED_CHARACTERS}")
