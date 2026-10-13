"""把RTL仿真实际输出的RGB888像素转为预览图，不重新实现绘图逻辑。"""
import argparse
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
pixels = args.source.read_text(encoding="ascii").splitlines()
if len(pixels) != 800 * 480:
    raise SystemExit(f"Expected 384000 active pixels, got {len(pixels)}")
data = bytes.fromhex("".join(pixels))
Image.frombytes("RGB", (800, 480), data).save(args.output)
print(f"PASS rendered RTL pixels: {args.output}")
