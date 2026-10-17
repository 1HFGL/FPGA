"""把RTL仿真实际输出的RGB888像素转为预览图，不重新实现绘图逻辑。"""
import argparse
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--width", type=int, default=800)
parser.add_argument("--height", type=int, default=480)
args = parser.parse_args()
if args.width <= 0 or args.height <= 0:
    raise SystemExit("Width and height must be positive")
pixels = args.source.read_text(encoding="ascii").splitlines()
expected = args.width * args.height
if len(pixels) != expected:
    raise SystemExit(f"Expected {expected} active pixels, got {len(pixels)}")
data = bytes.fromhex("".join(pixels))
Image.frombytes("RGB", (args.width, args.height), data).save(args.output)
print(f"PASS rendered RTL pixels: {args.output}")
