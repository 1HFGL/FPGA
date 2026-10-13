"""离线生成固定中文界面的24x24点阵Verilog；最终FPGA不依赖Python/字体文件。"""
import argparse
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

CHARACTERS = "电子钢琴吉他音量弯低中高区延开关实时波形1234567"
parser = argparse.ArgumentParser()
parser.add_argument("font", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
font = ImageFont.truetype(str(args.font), size=24)
font.set_variation_by_axes([500])  # Noto Sans SC 可变字重：medium
lines = [
    "// 中文24x24固定点阵；由 verification/scripts/generate_display_font.py 生成，不要手改字形。",
    "// 字形源：Noto Sans SC；Copyright 2014-2021 Adobe；SIL OFL 1.1。",
    "// 许可及来源：docs/display-font/OFL.txt、README.md。",
    "// font_sha256=" + hashlib.sha256(args.font.read_bytes()).hexdigest(),
    "module display_font24 (",
    "    input wire [5:0] glyph_id,",
    "    input wire [4:0] column, row,",
    "    output wire ink",
    ");",
    "    reg [575:0] glyph;",
    "    always @(*) begin",
    "        case (glyph_id)",
]
for index, char in enumerate(CHARACTERS, 1):
    canvas = Image.new("L", (24, 24), 0)
    box = font.getbbox(char)
    ox = (24 - (box[2] - box[0])) // 2 - box[0]
    oy = (24 - (box[3] - box[1])) // 2 - box[1]
    ImageDraw.Draw(canvas).text((ox, oy), char, fill=255, font=font)
    bits = "".join("1" if canvas.getpixel((x, y)) >= 96 else "0" for y in range(24) for x in range(24))
    lines.append(f"            6'd{index}: glyph=576'h{int(bits, 2):0144x}; // {char}")
lines.extend([
    "            default: glyph=576'd0;",
    "        endcase",
    "    end",
    "    // 行地址=24*row，用明确移位相加，避免工具给字体寻址分配DSP乘法器。",
    "    wire [9:0] row_offset={1'b0,row,4'b0}+{2'b0,row,3'b0};",
    "    wire [9:0] bit_index=10'd575-row_offset-{5'd0,column};",
    "    assign ink=(column<24 && row<24) ? glyph[bit_index] : 1'b0;",
    "endmodule",
])
args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Generated {len(CHARACTERS)} glyphs; order: {CHARACTERS}")
