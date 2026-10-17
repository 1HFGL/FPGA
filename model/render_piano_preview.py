"""生成钢琴感数字参考试听，绝不是板卡录音或最终发声链路。

使用相同1024点表、32位相位、Q1.16包络、向下取整增益和混音÷32。
不模拟UART事件调度、DAC模拟滤波/放大或整机延迟；不把试听文件烧入FPGA。
"""
import argparse
import math
from pathlib import Path
import struct
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host"))
from studio_model import cycle_samples, load_tone

FS = 48000
UNITY = 65536


def load_wave():
    tone = load_tone(ROOT / "host/tone_examples/piano.json")
    expected = [round(x * 32767) for x in cycle_samples(tone)]
    words = [int(x, 16) for x in (ROOT / "rtl/rom/piano_1024.mem").read_text().splitlines()]
    actual = [x if x < 32768 else x - 65536 for x in words]
    if actual != expected:
        raise ValueError("单周期波表与JSON不一致")
    return actual


def note_samples(table, note, held_samples, velocity=100):
    phase = 0
    increment = round(440 * 2 ** ((note - 69) / 12) * 2**32 / FS)
    velocity_gain = UNITY if velocity == 127 else velocity << 9
    amplitude = 0
    samples = []
    for n in range(1, held_samples + 1):
        amplitude = UNITY * n // 96 if n <= 96 else max(0, UNITY - UNITY * (n - 96) // 57600)
        raw = table[phase >> 22]
        phase = (phase + increment) & 0xFFFFFFFF
        samples.append(((raw * amplitude >> 16) * velocity_gain >> 16))
    release_start = amplitude
    for n in range(1, 8641):
        amplitude = release_start - release_start * n // 8640
        raw = table[phase >> 22]
        phase = (phase + increment) & 0xFFFFFFFF
        samples.append(((raw * amplitude >> 16) * velocity_gain >> 16))
    return samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/audio/piano_preview.wav")
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"不覆盖已有试听：{args.output}")
    table = load_wave()
    output = []
    # 原创短示例：逐音C/E/G/C，再四音和弦。数值保持低增益，不做额外响度归一化。
    for note in (60, 64, 67, 72):
        output.extend(x >> 5 for x in note_samples(table, note, 16800))
        output.extend([0] * 2880)
    voices = [note_samples(table, note, 38400) for note in (60, 64, 67, 72)]
    output.extend(sum(values) >> 5 for values in zip(*voices))
    output.extend([0] * 9600)
    if any(not -32768 <= value <= 32767 for value in output):
        raise ValueError("参考混音溢出")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(FS)
        stream.writeframes(struct.pack(f"<{len(output)}h", *output))
    peak = max(abs(x) for x in output)
    rms = math.sqrt(sum(x*x for x in output) / len(output))
    print(f"REFERENCE ONLY: {args.output}; frames={len(output)} duration={len(output)/FS:.3f}s peak={peak} rms={rms:.3f}")


if __name__ == "__main__":
    main()
