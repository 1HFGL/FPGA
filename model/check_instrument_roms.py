"""独立核对吉他拨弦感 / 弦乐持续感 ROM 的逐点数值与频谱。

不导入生成器或 RTL 参考模型。频谱来自单周期表，并非上板测量；
该检查证明谐波组成不同，不把它当作真实乐器仿真或主观试听结论。
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re


def load(path):
    words = path.read_text(encoding="ascii").split()
    if len(words) != 1024:
        raise ValueError(f"{path}: expected 1024 samples, got {len(words)}")
    result = []
    for index, word in enumerate(words):
        if not re.fullmatch(r"[0-9a-fA-F]{4}", word):
            raise ValueError(f"{path}: invalid signed-16 word at address {index}: {word!r}")
        unsigned = int(word, 16)
        result.append(unsigned if unsigned < 32768 else unsigned - 65536)
    return result


def ideal(index, preset):
    t = 2 * math.pi * index / 1024
    # 直接展开设计公式，避免与生成器共享数组或运算函数。
    if preset == "guitar":
        value = (16 * math.sin(t) + 8 * math.sin(2*t) + 4 * math.sin(3*t)
                 + 2 * math.sin(5*t) + math.sin(6*t) + math.sin(7*t))
    elif preset == "strings":
        value = (16 * math.sin(t) + 6 * math.sin(2*t) + 3 * math.sin(3*t)
                 + 2 * math.sin(4*t) + 2 * math.sin(5*t) + math.sin(6*t)
                 + math.sin(7*t) + math.sin(8*t))
    else:
        raise ValueError(f"Unknown preset {preset}")
    return value * 32767 / 32


def quantize(value):
    magnitude = int(abs(value) + 0.5)
    return -magnitude if value < 0 else magnitude


def dft_amplitude(samples, harmonic):
    re_part = math.fsum(value * math.cos(2 * math.pi * harmonic * i / 1024)
                        for i, value in enumerate(samples))
    im_part = math.fsum(value * math.sin(2 * math.pi * harmonic * i / 1024)
                        for i, value in enumerate(samples))
    return math.hypot(re_part, im_part) / 512


def verify(path, preset):
    samples = load(path)
    maximum_error = 0.0
    for index, actual in enumerate(samples):
        value = ideal(index, preset)
        expected = quantize(value)
        if actual != expected:
            raise ValueError(f"{preset} address {index}: actual {actual}, expected {expected}")
        maximum_error = max(maximum_error, abs(actual-value))
    if maximum_error > 0.500000001:
        raise ValueError(f"{preset}: quantization error exceeds half an LSB")
    if sum(samples) != 0 or samples[0] != 0 or samples[512] != 0:
        raise ValueError(f"{preset}: DC or phase crossing mismatch")
    if not (-32767 <= min(samples) < 0 < max(samples) <= 32767):
        raise ValueError(f"{preset}: signed output range mismatch")
    for index in range(1, 512):
        if samples[index] != -samples[1024-index]:
            raise ValueError(f"{preset}: phase reflection symmetry mismatch at {index}")
    amplitudes = [dft_amplitude(samples, h) for h in range(1, 17)]
    weights = (16, 8, 4, 0, 2, 1, 1, 0) if preset == "guitar" else (16, 6, 3, 2, 2, 1, 1, 1)
    for harmonic, amplitude in enumerate(amplitudes, 1):
        target = 32767 * weights[harmonic-1] / 32 if harmonic <= 8 else 0
        # 每个样本误差 <= 0.5 LSB，因此任意 DFT 幅度误差不超过 1 LSB。
        if abs(amplitude-target) > 1.0:
            raise ValueError(f"{preset} H{harmonic}: actual {amplitude}, expected {target}")
    ratios = [amplitude/amplitudes[0] for amplitude in amplitudes[:8]]
    result = dict(preset=preset, count=len(samples), minimum=min(samples), maximum=max(samples),
                  dc_sum=sum(samples), max_quantization_error_lsb=maximum_error,
                  harmonic_amplitudes_1_to_16=amplitudes,
                  harmonic_ratios_1_to_8=ratios,
                  sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    print(f"PASS {preset}: 1024 exact samples, DC=0, range={min(samples)}..{max(samples)}, "
          f"max quantization error={maximum_error:.9f} LSB")
    print("  H1..H8 amplitude=" + ", ".join(f"{value:.6f}" for value in amplitudes[:8]))
    print("  H1..H8/H1=" + ", ".join(f"{value:.6f}" for value in ratios))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--report", type=Path, help="optional JSON evidence path")
    args = parser.parse_args()
    results = [verify(args.root / f"rtl/rom/{name}_1024.mem", name)
               for name in ("guitar", "strings")]
    # 相同的基波目标幅度，且 H4 是直接可测的不同成分。
    if abs(results[0]["harmonic_amplitudes_1_to_16"][0]
           - results[1]["harmonic_amplitudes_1_to_16"][0]) > 2.0:
        raise ValueError("Fundamental amplitudes unexpectedly differ")
    if results[0]["harmonic_ratios_1_to_8"][3] > 0.0001 or not 0.1249 < results[1]["harmonic_ratios_1_to_8"][3] < 0.1251:
        raise ValueError("Expected H4 distinction is missing")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(dict(scope="mathematical single-cycle ROM verification; no hardware or listening claim", presets=results), indent=2)+"\n", encoding="utf-8")
    print("PASS two instrument preset ROMs: independent equations, 2048 samples, matched fundamental, distinct harmonics.")


if __name__ == "__main__":
    main()
