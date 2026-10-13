"""独立整数参考：128 MIDI 步长与真实四声部 RTL trace，无第三方库。"""
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / "rtl/control/note_phase_lut.v").read_text(encoding="utf-8")
    table = {int(n): int(v) for n, v in re.findall(r"7'd(\d+): phase_inc = 32'd(\d+)", source)}
    assert len(table) == 128
    for n in range(128):
        assert table[n] == round(440 * 2 ** ((n - 69) / 12) * 2**32 / 48000)
    phase, env = [0] * 4, [0] * 4
    samples = resets = positive = negative = 0
    for line in (ROOT / "build/regression/logs/abc_mix_trace.txt").read_text(encoding="ascii").splitlines():
        if line == "reset":
            phase, env = [0] * 4, [0] * 4
            resets += 1
            continue
        fields = list(map(int, line.split()))
        assert len(fields) == 13
        total = 0
        for v in range(4):
            gate, note, velocity = fields[v * 3 : v * 3 + 3]
            assert gate in (0, 1) and 0 <= note < 128 and 0 <= velocity < 128
            env[v] = min(255, env[v] + 8) if gate else max(0, env[v] - 4)
            s = 32767 * math.sin(2 * math.pi * (phase[v] >> 22) / 1024)
            raw = math.floor(s + 0.5) if s >= 0 else math.ceil(s - 0.5)
            total += (raw * env[v] * velocity) >> 15
            phase[v] = (phase[v] + table[note]) & 0xFFFFFFFF
        expected = total >> 5
        actual = fields[-1]
        assert actual == expected, f"sample {samples}: actual={actual}, expected={expected}"
        assert -4049 <= actual <= 4049
        samples += 1
        positive += actual > 0
        negative += actual < 0
    assert samples == 745 and resets == 2 and positive and negative
    print(f"PASS Python ABC reference: 128 notes, {samples} mixed samples, {resets} resets")


if __name__ == "__main__":
    main()
