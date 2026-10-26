"""离线生成“静奏”界面的 2bit 覆盖度字模。

与 generate_display_font24.py 的区别：
- 每个像素保留 2bit 覆盖度（0=背景，3=满墨），供 FPGA 做一次线性混合，
  小字号与大标题都有平滑边缘，而不是把 1bit 点阵整数放大。
- 24px 文本层：64 槽（0 为空白），每行 24 像素 × 2bit = 48bit，
  地址 {glyph[5:0], row[4:0]}。
- 48px 标题层：8 槽（0 为空白），每行 48 像素 × 2bit = 96bit，
  地址 {title[2:0], row[5:0]}。

像素端按 16bit 平面切分：文本行是 3 个平面、标题行是 6 个平面，
绘制器用覆盖度 0..3 选一个平面，只需 3:1 或 6:1 的窄选择，
不需要 48/96 位整行的可变移位。

生成依据、字体 SHA256 与许可见 docs/display-font/README.md；
FPGA 不读系统字体文件，只读综合进片内 ROM 的固定点阵。
"""
import argparse
import hashlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# 24px 文本层：顺序即 1 起的字形编号，0 号固定空白。
# 编号分组（绘制器按同一顺序引用）：
#   1-6 标题用字：电 子 钢 琴 吉 他
#   7-8 状态：静 奏
#   9-12 参数：音 量 弯 半
#   13-16 音区：低 中 高 区
#   17-19 开关：延 开 关
#   20-30 波形：实 时 波 形 倍 率 复 声 部 就 绪
#   31-39 指位：拨 弦 指 位 示 意 输 出 平
#   40-46 音名：C D E F G A B
#   47 倍率符号 x；48-57 数字 0-9
TEXT_CHARACTERS = (
    "电子钢琴吉他"      # 1-6
    "静奏"              # 7-8
    "音量弯半"          # 9-12
    "低中高区"          # 13-16
    "延开关"            # 17-19
    "实时波形"          # 20-23
    "倍率"              # 24-25
    "复声部就绪"        # 26-30
    "拨弦指位示意"      # 31-36
    "输出平"            # 37-39
    "CDEFGAB"           # 40-46
    "x"                 # 47
    "0123456789"        # 48-57
    "明亮度原触摸"      # 58-63
)
# 48px 标题层：1 起编号；绘制器按音色选“电子钢琴/电子吉他”。
TITLE_CHARACTERS = "电子钢琴吉他"

parser = argparse.ArgumentParser()
parser.add_argument("font", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--digits-font", type=Path, help="等宽数字字体（可选）")
parser.add_argument("--append-practice-only", action="store_true", help="补64..83练习字形，保护原正文和标题")
parser.add_argument("--append-touch-only", action="store_true", help="仅填充58..63槽，保留已发布数字和标题")
args = parser.parse_args()

assert len(TEXT_CHARACTERS) <= 63, "文本层最多 63 个字形（0 号空白）"
assert len(TITLE_CHARACTERS) <= 7, "标题层最多 7 个字形（0 号空白）"


def quantize(value):
    """把 0..255 的面积覆盖度映射到 0..3。

    线性 (value*4)//256 会把细笔画（面积很小但笔画连续）压成 0，
    24px 中文几乎消失。这里用面积阈值：任何可见覆盖至少记 1，
    中等覆盖记 2，接近满墨记 3，保证笔画连续且边缘仍有层次。
    纯黑保留 0，纯白得到 3，满墨像素与文字色完全相同。
    """
    if value >= 150:
        return 3
    if value >= 70:
        return 2
    if value >= 20:
        return 1
    if value > 0:
        return 1
    return 0


def coverage(font, char, size):
    """渲染为 0..3 的覆盖度；4 倍超采样后按面积量化，避免细笔画断裂。

    getbbox 已是像素坐标（与字号的缩放无关），因此不加 scale：
    超采样画布上直接按 (canvas_size - bbox_size)/2 - bbox_origin 摆放，
    否则偏移会被乘以 scale，字形被挤到画布边缘甚至裁掉。
    """
    scale = 4
    # 字号与画布一起放大，才能在降采样时得到真正的面积覆盖度；
    # 只放大画布会把 24px 字形留在 96px 画布的左上角。
    big_font = ImageFont.truetype(font.path, size=size * scale)
    # Noto Sans SC 是可变字体；不指定字重会落到很细的默认轴，中文笔画会断开。
    # 与旧 24x24 字库保持同一 Medium(500) 字重，保证两种字号观感一致。
    try:
        big_font.set_variation_by_axes([500])
    except Exception:
        pass

    canvas = Image.new("L", (size * scale, size * scale), 0)
    box = big_font.getbbox(char)
    ox = (size * scale - (box[2] - box[0])) // 2 - box[0]
    oy = (size * scale - (box[3] - box[1])) // 2 - box[1]
    ImageDraw.Draw(canvas).text((ox, oy), char, fill=255, font=big_font)
    canvas = canvas.resize((size, size), Image.BOX)
    return [quantize(value) for value in canvas.getdata()]


def rows_for(chars, size, font, digits_font):
    """返回 [(槽号, 行号, 行像素值)]，行内高位是屏幕左侧像素。"""
    result = []
    for slot, char in enumerate(chars, 1):
        glyph_font = digits_font if char.isascii() and digits_font else font
        pixels = coverage(glyph_font, char, size)
        for row in range(size):
            value = 0
            for column in range(size):
                value = (value << 2) | pixels[row * size + column]
            result.append((slot, row, value, char))
    return result


font_path = args.font
if args.append_practice_only or args.append_touch_only:
    import re
    body=args.output.read_text(encoding='utf-8')
    sha=hashlib.sha256(font_path.read_bytes()).hexdigest()
    assert f'text_font_sha256={sha}' in body, 'Use the original Chinese font'
    old=body
    body=re.sub(r"        text_rom\[(\d+)\]\s*=\s*48'h[0-9a-f]+;[^\n]*\n",
                lambda m:'' if (int(m[1])>=64*32 if args.append_practice_only else 58*32<=int(m[1])<64*32) else m[0],body)
    offset=63 if args.append_practice_only else 57
    chars='内置曲下载未开始暂停继续重来拍速完成预备' if args.append_practice_only else TEXT_CHARACTERS[57:]
    rows=rows_for(chars,24,ImageFont.truetype(str(font_path),24),None)
    if args.append_practice_only:
        body=body.replace('input wire [5:0] text_glyph','input wire [6:0] text_glyph').replace('text_rom [0:2047]','text_rom [0:4095]')
        if not re.search(r'init_index\s*=\s*2048;',body):
            anchor_zero='        for (init_index = 0; init_index < 512;'
            body=body.replace(anchor_zero,"        for (init_index = 2048; init_index < 3072; init_index = init_index + 1) text_rom[init_index] = 48'd0;\n        for (init_index = 3072; init_index < 4096; init_index = init_index + 1) text_rom[init_index] = 48'd0;\n"+anchor_zero)
    lines=[f"        text_rom[{((slot+offset)<<5)|row}] = 48'h{value:012x}; // {char} 第{row}行" for slot,row,value,char in rows]
    anchor='    end\n    // 一拍同步读'
    assert body.count(anchor)==1
    body=body.replace(anchor,'\n'.join(lines)+'\n'+anchor)
    # Reproducible append; neither the original 57 glyphs nor title rows can change.
    protected=lambda s:[l for l in s.splitlines() if 'title_rom[' in l or
        (re.search(r'text_rom\[(\d+)\] =',l) and int(re.search(r'text_rom\[(\d+)\]',l)[1])<(64*32 if args.append_practice_only else 58*32))]
    assert protected(body)==protected(old)
    args.output.write_text(body,encoding='utf-8',newline='\n')
    print('PASS appended glyphs; original text/title rows unchanged')
    raise SystemExit(0)
text_rows = rows_for(TEXT_CHARACTERS, 24, ImageFont.truetype(str(font_path), 24),
                     ImageFont.truetype(str(args.digits_font), 24) if args.digits_font else None)
title_rows = rows_for(TITLE_CHARACTERS, 48, ImageFont.truetype(str(font_path), 48), None)

lines = [
    "// 2bit 覆盖度字模：由 verification/scripts/generate_ui_fonts.py 生成，不要手改。",
    "// 字形源：Noto Sans SC（SIL OFL 1.1）；数字可用 Red Hat Mono（SIL OFL 1.1）。",
    f"// text_font_sha256={hashlib.sha256(font_path.read_bytes()).hexdigest()}",
    f"// digits_font_sha256={hashlib.sha256((args.digits_font or font_path).read_bytes()).hexdigest()}",
    "// 文本层 64×24 行、88bit 槽；标题层 8×48 行、96bit 行。",
    "// 未写入的槽与行保持 0，由 initial 只对用到的行赋值；缺字表现为空白而不是垃圾。",
    "module display_font_ui (",
    "    input wire pixel_clk,",
    "    input wire [5:0] text_glyph,",
    "    input wire [4:0] text_row,",
    "    output reg [47:0] text_bits,",
    "    input wire [2:0] title_glyph,",
    "    input wire [5:0] title_row,",
    "    output reg [95:0] title_bits",
    ");",
    "    reg [47:0] text_rom [0:2047];",
    "    reg [95:0] title_rom [0:511];",
    "    integer init_index;",
    "    initial begin",
    "        // 先整体清零再写字形：未写到的行（字形内部空白）必须是 0，不能留下 X。",
    "        // 分成两个 1024 次循环，遵守综合工具默认 2000 次展开限制。",
    "        for (init_index = 0; init_index < 1024; init_index = init_index + 1)",
    "            text_rom[init_index] = 48'd0;",
    "        for (init_index = 1024; init_index < 2048; init_index = init_index + 1)",
    "            text_rom[init_index] = 48'd0;",
    "        for (init_index = 0; init_index < 512; init_index = init_index + 1)",
    "            title_rom[init_index] = 96'd0;",
]
for slot, row, value, char in text_rows:
    lines.append(f"        text_rom[{(slot << 5) | row}] = 48'h{value:012x}; // {char} 第{row}行")
for slot, row, value, char in title_rows:
    lines.append(f"        title_rom[{(slot << 6) | row}] = 96'h{value:024x}; // {char} 第{row}行")
lines += [
    "    end",
    "    // 一拍同步读，与 instrument_display 的 P1 级对齐；不新增像素流水级。",
    "    always @(posedge pixel_clk) begin",
    "        text_bits <= text_rom[{text_glyph, text_row}];",
    "        title_bits <= title_rom[{title_glyph, title_row}];",
    "    end",
    "endmodule",
]
args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Generated {args.output}: {len(TEXT_CHARACTERS)} text glyphs, {len(TITLE_CHARACTERS)} title glyphs")
