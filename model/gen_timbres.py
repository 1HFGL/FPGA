"""Generate the bright single-cycle ROM; --check never modifies either ROM.

Python only prepares constant ROM contents. FPGA DDS, ADSR and mixing still
produce every audio sample at run time; these are not prerecorded audio files.
"""

import argparse
import math
from pathlib import Path
import re


TABLE_SIZE = 1024
MAX_SAMPLE = 32767


def round_away(value):
    """Match gen_sine.ps1: round halves away from zero, not Python's ties-even."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def make_table(bright):
    result = []
    for address in range(TABLE_SIZE):
        angle = 2.0 * math.pi * address / TABLE_SIZE
        if bright:
            # Sum of absolute weights is 15: the waveform cannot exceed unity.
            value = MAX_SAMPLE * sum(
                weight * math.sin(harmonic * angle)
                for harmonic, weight in enumerate((8, 4, 2, 1), start=1)
            ) / 15.0
        else:
            value = MAX_SAMPLE * math.sin(angle)
        quantized = round_away(value)
        if not -32767 <= quantized <= 32767:
            raise ValueError(f"Out-of-range generated sample at address {address}")
        result.append(quantized)
    return result


def check_table(path, expected):
    words = path.read_text(encoding="ascii").split()
    if len(words) != TABLE_SIZE:
        raise ValueError(f"{path}: expected {TABLE_SIZE} words, found {len(words)}")
    for address, (word, value) in enumerate(zip(words, expected)):
        if not re.fullmatch(r"[0-9a-fA-F]{4}", word):
            raise ValueError(f"{path}: invalid signed-16-bit hex word at {address}")
        actual = int(word, 16)
        if actual >= 32768:
            actual -= 65536
        if actual != value:
            raise ValueError(f"{path}: sample {address} is {actual}, expected {value}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="verify both ROMs without writing")
    args = parser.parse_args()
    soft_path = args.root / "rtl/rom/sine_1024.mem"
    bright_path = args.root / "rtl/rom/bright_1024.mem"
    soft, bright = make_table(False), make_table(True)
    # Preserve the existing sine ROM exactly, including its established format.
    check_table(soft_path, soft)
    if not args.check:
        bright_path.parent.mkdir(parents=True, exist_ok=True)
        bright_path.write_text("".join(f"{value & 65535:04X}\n" for value in bright), encoding="ascii")
    check_table(bright_path, bright)
    action = "checked" if args.check else "generated bright and checked"
    print(f"PASS timbre ROM generator: {action} 1024 soft + 1024 bright samples; sine preserved.")


if __name__ == "__main__":
    main()
