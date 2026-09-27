"""Check the ROM and exported RTL DDS samples using Python 3 standard library."""
import argparse
import math
from pathlib import Path


def sine_sample(address):
    value = 32767 * math.sin(2 * math.pi * address / 1024)
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path, default=root / "results/logs/dds_trace.txt")
    args = parser.parse_args()
    words = (root / "rtl/rom/sine_1024.mem").read_text(encoding="ascii").split()
    if len(words) != 1024:
        raise ValueError(f"Expected 1024 ROM values, got {len(words)}")
    for address, word in enumerate(words):
        unsigned = int(word, 16)
        if not 0 <= unsigned <= 65535:
            raise ValueError(f"ROM word out of range at {address}")
        actual = unsigned if unsigned < 32768 else unsigned - 65536
        if actual != sine_sample(address):
            raise ValueError(f"ROM mismatch at address {address}")
    phase, samples, resets = 0, 0, 0
    for line_no, line in enumerate(args.trace.read_text(encoding="ascii").splitlines(), 1):
        rst, increment, actual = map(int, line.split())
        if rst not in (0, 1) or not 0 <= increment <= 0xFFFFFFFF:
            raise ValueError(f"Invalid stimulus at trace line {line_no}")
        if rst:
            phase, expected = 0, 0
            resets += 1
        else:
            expected = sine_sample(phase >> 22)
            phase = (phase + increment) & 0xFFFFFFFF
            samples += 1
        if actual != expected:
            raise ValueError(f"Trace line {line_no}: sample {actual}, expected {expected}")
    if samples != 4810 or resets == 0:
        raise ValueError(f"Incomplete trace: {samples} samples, {resets} reset records")
    print(f"PASS Python reference: 1024 ROM entries, {samples} RTL samples, {resets} reset records.")


if __name__ == "__main__":
    main()
