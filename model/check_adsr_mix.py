"""四声部独立参考：直线包络、数学正弦、两级定点缩放；只用于开发验证。"""
import math
from pathlib import Path
from check_adsr import Envelope


def main():
    root = Path(__file__).resolve().parents[1]
    envelopes = [Envelope() for _ in range(4)]
    phases = [0] * 4
    count = resets = 0
    seen = [set() for _ in range(4)]
    for line in (root / "results/logs/adsr_mix_trace.txt").read_text(encoding="ascii").splitlines():
        if line == "reset":
            envelopes = [Envelope() for _ in range(4)]
            phases = [0] * 4
            resets += 1
            continue
        fields = list(map(int, line.split()))
        assert len(fields) == 23
        total = done = 0
        active = False
        for voice in range(4):
            gate, trigger, note, velocity, actual_level = fields[voice*5:voice*5+5]
            envelope = envelopes[voice]
            envelope.clock(True, gate, trigger)
            assert actual_level == envelope.level, (count, voice, actual_level, envelope.level)
            seen[voice].add(envelope.state)
            value = 32767 * math.sin(2 * math.pi * (phases[voice] >> 22) / 1024)
            raw = math.floor(value + .5) if value >= 0 else math.ceil(value - .5)
            voice_sample = (raw * envelope.level) // 65536
            scaled = (voice_sample * velocity) // 128
            total += scaled
            step = round(440 * 2 ** ((note - 69) / 12) * 2**32 / 48000)
            phases[voice] = (phases[voice] + step) & 0xffffffff
            finished = not gate and envelope.state == 0 and scaled == 0
            done |= int(finished) << voice
            active |= bool(gate or envelope.state != 0 or not finished)
        expected = (total >> 5, done, int(active))
        actual = tuple(fields[-3:])
        assert actual == expected, f"sample {count}: actual={actual}, expected={expected}"
        assert -4064 <= actual[0] <= 4063
        count += 1
    assert count > 60000 and resets == 2 and all(states == set(range(5)) for states in seen)
    assert actual == (0, 15, 0)
    print(f"PASS Python ADSR mix: {count} samples, four independent envelopes, {resets} resets")


if __name__ == "__main__":
    main()
