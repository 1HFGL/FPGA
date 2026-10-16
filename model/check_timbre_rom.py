"""Independently verify two single-cycle ROMs and their harmonic distinction.

No generator or RTL model is imported. Equations below are the public waveform
contract. DFT measurements describe the stored waveforms, not board recordings.
"""

import argparse
import math
from pathlib import Path
import re


def load_samples(path):
    words = path.read_text(encoding="ascii").split()
    if len(words) != 1024:
        raise ValueError(f"{path}: expected 1024 samples, got {len(words)}")
    samples = []
    for index, word in enumerate(words):
        if not re.fullmatch(r"[0-9a-fA-F]{4}", word):
            raise ValueError(f"{path}: invalid 16-bit word at {index}: {word!r}")
        value = int(word, 16)
        samples.append(value if value < 32768 else value - 65536)
    return samples


def expected_sample(index, bright):
    theta = (2 * math.pi * index) / 1024
    if bright:
        value = 32767 * (
            8 * math.sin(theta) + 4 * math.sin(2 * theta)
            + 2 * math.sin(3 * theta) + math.sin(4 * theta)
        ) / 15
    else:
        value = 32767 * math.sin(theta)
    # Independent expression of round-half-away-from-zero.
    magnitude = int(abs(value) + 0.5)
    return -magnitude if value < 0 else magnitude


def amplitude(samples, harmonic):
    size = len(samples)
    real = math.fsum(sample * math.cos(2 * math.pi * harmonic * i / size)
                     for i, sample in enumerate(samples))
    imag = math.fsum(sample * math.sin(2 * math.pi * harmonic * i / size)
                     for i, sample in enumerate(samples))
    return 2 * math.hypot(real, imag) / size


def verify(name, path, bright):
    samples = load_samples(path)
    for index, actual in enumerate(samples):
        expected = expected_sample(index, bright)
        if actual != expected:
            raise ValueError(f"{name} address {index}: actual {actual}, expected {expected}")
    if sum(samples) != 0:
        raise ValueError(f"{name}: nonzero DC sum {sum(samples)}")
    if not (-32767 <= min(samples) < 0 < max(samples) <= 32767):
        raise ValueError(f"{name}: missing polarity or invalid peak")
    if samples[0] != 0 or samples[512] != 0:
        raise ValueError(f"{name}: phase-zero / half-cycle crossing is not zero")
    for index in range(1, 512):
        if samples[index] != -samples[1024 - index]:
            raise ValueError(f"{name}: phase reflection symmetry broken at {index}")
    harmonics = [amplitude(samples, h) for h in range(1, 13)]
    ideal = [32767 * weight / 15 for weight in (8, 4, 2, 1)] if bright else [32767, 0, 0, 0]
    for h, (measured, target) in enumerate(zip(harmonics, ideal), 1):
        # Quantization error is at most 0.5 LSB per entry, so 1 LSB is a strict
        # conservative amplitude bound for any one DFT component.
        if abs(measured - target) > 1.0:
            raise ValueError(f"{name}: harmonic {h} amplitude {measured} differs from {target}")
    if max(harmonics[4:]) > 1.0:
        raise ValueError(f"{name}: unexpected harmonics 5..12 exceed quantization bound")
    ratios = [level / harmonics[0] for level in harmonics[:4]]
    print(f"PASS {name}: 1024 exact samples; DC=0; min/max={min(samples)}/{max(samples)}")
    print("  H1..H4 amplitude=" + ", ".join(f"{level:.6f}" for level in harmonics[:4]))
    print("  H1..H4 / H1=" + ", ".join(f"{ratio:.6f}" for ratio in ratios))
    return samples, harmonics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    _, soft = verify("soft", args.root / "rtl/rom/sine_1024.mem", False)
    _, bright = verify("bright", args.root / "rtl/rom/bright_1024.mem", True)
    # This tests waveform composition, not subjective listening or loudness.
    if soft[1] / soft[0] > 0.0001 or bright[1] / bright[0] < 0.49:
        raise ValueError("Two tables do not have the expected spectral distinction")
    print("PASS two timbres: soft is sinusoidal; bright contains harmonics 2, 3 and 4.")
    print("Scope: mathematical ROM spectrum only; listening and board audio remain separate checks.")


if __name__ == "__main__":
    main()
