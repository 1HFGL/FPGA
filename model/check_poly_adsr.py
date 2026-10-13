"""四声部真实 RTL 轨迹的独立数学参考；仅使用 Python 标准库。"""
import argparse
import math
from pathlib import Path
import re

from check_adsr import Envelope


def sine_sample(phase):
    value = 32767 * math.sin(2 * math.pi * (phase >> 22) / 1024)
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def velocity_gain(value):
    return 65536 if value == 127 else value * 512


def check_trace(path, boundary=False):
    with path.open(encoding="ascii") as trace:
        header = trace.readline().strip()
        match = re.fullmatch(r"# poly_adsr v1 A=(\d+) D=(\d+) S=(\d+) R=(\d+) SHIFT=(\d+)", header)
        if not match:
            raise AssertionError(f"{path}: missing configuration header")
        a, d, s, r, shift = map(int, match.groups())
        expected_config = (0, 1, 70000, 1, 0) if boundary else (96, 24000, 6554, 5760, 5)
        if (a, d, s, r, shift) != expected_config:
            raise AssertionError(f"Unexpected test configuration: {match.groups()}")
        a, d, s, r = max(a, 1), max(d, 1), min(s, 65536), max(r, 1)

        def reset_state():
            envs = [Envelope() for _ in range(4)]
            for env in envs:
                env.ATTACK, env.DECAY, env.SUSTAIN, env.RELEASE = a, d, s, r
            return envs, [0] * 4, None, None, None, [0] * 4, [0] * 4, [False] * 4, 0

        envs, phases, raw_q, voice_q, gain_q, voice_values, gain_values, mixed_nonzero, sample = reset_state()
        clocks = samples = resets = positive = negative = positive_clip = negative_clip = 0
        states = [set() for _ in range(4)]
        completed = [dict(attack=set(), decay=set(), release=set()) for _ in range(4)]
        footer = None
        for line in trace:
            if line.startswith("# completed "):
                footer = line.strip()
                if trace.read().strip():
                    raise AssertionError("Data after completion footer")
                break
            fields = list(map(int, line.split()))
            if len(fields) != 16:
                raise AssertionError("Malformed clock record")
            reset_n, request, gates, triggers, notes, velocities = fields[:6]
            observed = tuple(fields[6:])
            if reset_n not in (0, 1) or request not in (0, 1):
                raise AssertionError("Non-binary reset/request")
            if not (0 <= gates < 16 and 0 <= triggers < 16 and
                    0 <= notes < 2**28 and 0 <= velocities < 2**28):
                raise AssertionError("Invalid control field width")
            clocks += 1
            clip = False
            if not reset_n:
                envs, phases, raw_q, voice_q, gain_q, voice_values, gain_values, mixed_nonzero, sample = reset_state()
                valid, active, released, sounding = False, 0, 15, False
                resets += 1
            else:
                valid = gain_q is not None
                if valid:
                    shifted = sum(gain_q) // 2**shift
                    clip = not -32768 <= shifted <= 32767
                    sample = max(-32768, min(32767, shifted))
                    mixed_nonzero = [value != 0 for value in gain_q]
                next_gain = None if voice_q is None else [
                    value * velocity_gain(velocity) // 65536
                    for value, velocity in voice_q
                ]
                next_voice = raw_q
                if next_gain is not None:
                    gain_values = next_gain
                if next_voice is not None:
                    voice_values = [item[0] for item in next_voice]
                next_raw = []
                active = released = 0
                for v, env in enumerate(envs):
                    gate, trigger = (gates >> v) & 1, (triggers >> v) & 1
                    env.clock(request, gate, trigger)
                    states[v].add(env.state)
                    if request and env.segment:
                        target = {"attack": 2, "decay": 3, "release": 0}[env.segment]
                        if env.state == target:
                            completed[v][env.segment].add(env.age)
                    if request:
                        note = (notes >> (7 * v)) & 127
                        velocity = (velocities >> (7 * v)) & 127
                        next_raw.append((sine_sample(phases[v]) * env.level // 65536, velocity))
                        inc = round(440 * 2 ** ((note - 69) / 12) * 2**32 / 48000)
                        phases[v] = (phases[v] + inc) % 2**32
                    busy = (gate or env.state != 0 or
                            (next_voice is not None and voice_values[v] != 0) or
                            (next_gain is not None and gain_values[v] != 0) or mixed_nonzero[v])
                    active |= int(bool(busy)) << v
                    released |= int(not gate and not busy) << v
                raw_q, voice_q, gain_q = next_raw if request else None, next_voice, next_gain
                sounding = bool(active)
            expected = (sample, int(valid), int(clip), active, released, int(sounding),
                        *(env.level for env in envs))
            if observed != expected:
                raise AssertionError(f"{path.name} clock {clocks}: actual={observed}, expected={expected}")
            if valid:
                samples += 1
                positive += sample > 0
                negative += sample < 0
                positive_clip += clip and sample == 32767
                negative_clip += clip and sample == -32768
        expected_footer = f"# completed clocks={clocks} samples={samples} resets={resets}"
        if footer != expected_footer:
            raise AssertionError(f"Incomplete trace: {footer!r}, expected {expected_footer!r}")
        if clocks < 4000 or samples < 1000 or resets < 4 or not (positive and negative):
            raise AssertionError("Missing clock/sample/reset/signed coverage")
        if not boundary:
            if states != [set(range(5)) for _ in range(4)]:
                raise AssertionError(f"Missing independent envelope stages: {states}")
            if any(durations != {"attack": {a}, "decay": {d}, "release": {r}} for durations in completed):
                raise AssertionError(f"Missing exact per-voice durations: {completed}")
            if positive_clip or negative_clip:
                raise AssertionError("Quiet mix should not saturate")
        elif not (positive_clip and negative_clip):
            raise AssertionError("Missing positive/negative clipping")
        if sample != 0 or active != 0 or released != 15 or any(env.level for env in envs):
            raise AssertionError("Final tails are not drained")
        print(f"PASS Python poly ADSR {'boundary' if boundary else 'default'}: "
              f"{clocks} clocks, {samples} samples, {resets} resets, "
              f"clips +{positive_clip}/-{negative_clip}.")


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--default-trace", type=Path, default=root / "build/regression/logs/poly_adsr_default_trace.txt")
    parser.add_argument("--boundary-trace", type=Path, default=root / "build/regression/logs/poly_adsr_boundary_trace.txt")
    args = parser.parse_args()
    check_trace(args.default_trace)
    check_trace(args.boundary_trace, boundary=True)


if __name__ == "__main__":
    main()
