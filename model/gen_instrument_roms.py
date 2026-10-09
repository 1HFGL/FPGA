"""生成两张乐器预设的单周期 ROM；--check 只核对，不写入文件。

这些是 1024 点周期函数常量，并非录制的乐器音频。FPGA 仍实时完成
相位累加、亮度变化、ADSR、力度和四声部混音。
"""

import argparse
import math
from pathlib import Path
import re


SIZE = 1024
PRESETS = {
    "guitar": (16, 8, 4, 0, 2, 1, 1, 0),
    "strings": (16, 6, 3, 2, 2, 1, 1, 1),
}


def generate(weights):
    if sum(abs(weight) for weight in weights) != 32:
        raise ValueError("Expected absolute harmonic weights to sum to 32")
    table = []
    for address in range(SIZE):
        angle = 2.0 * math.pi * address / SIZE
        value = 32767.0 / 32.0 * sum(
            weight * math.sin(harmonic * angle)
            for harmonic, weight in enumerate(weights, 1)
        )
        # 与既有正弦表一致：恰好半 LSB 时远离零舍入。
        sample = math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)
        if not -32767 <= sample <= 32767:
            raise ValueError(f"Sample overflow at address {address}: {sample}")
        table.append(sample)
    return table


def verify(path, expected):
    words = path.read_text(encoding="ascii").split()
    if len(words) != SIZE:
        raise ValueError(f"{path}: expected {SIZE} entries, got {len(words)}")
    for address, (word, want) in enumerate(zip(words, expected)):
        if not re.fullmatch(r"[0-9A-Fa-f]{4}", word):
            raise ValueError(f"{path}: invalid 16-bit word at {address}: {word!r}")
        value = int(word, 16)
        actual = value if value < 32768 else value - 65536
        if actual != want:
            raise ValueError(f"{path}: address {address}: actual {actual}, expected {want}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="verify ROMs without writing")
    args = parser.parse_args()
    for name, weights in PRESETS.items():
        samples = generate(weights)
        path = args.root / f"rtl/rom/{name}_1024.mem"
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("".join(f"{sample & 65535:04X}\n" for sample in samples), encoding="ascii")
        verify(path, samples)
        print(f"PASS {name} ROM: 1024 samples, {'checked' if args.check else 'generated and checked'}.")
    print("Existing sine_1024.mem and bright_1024.mem are never written by this generator.")


if __name__ == "__main__":
    main()
