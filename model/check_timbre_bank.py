"""逐时钟核对两音色四声部 RTL 轨迹，使用闭式包络和数学谐波参考。"""
import argparse
import math
from pathlib import Path
import re

from check_adsr import Envelope


CONFIGURATIONS = {
    "short": (8, 17, 20000, 11, 5),
    "boundary": (0, 1, 70000, 1, 0),
    "zero": (8, 17, 0, 11, 5),
}


def oscillator(phase, bright, increment):
    """独立计算，不读取受测 ROM；先限制最高谐波，再按地址量化相位。"""
    theta = 2 * math.pi * (phase >> 22) / 1024
    if bright and increment < 2**29:
        value = 32767 * sum(weight * math.sin(h * theta)
                            for h, weight in enumerate((8, 4, 2, 1), 1)) / 15
    else:
        value = 32767 * math.sin(theta)
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def check_trace(path, name):
    with path.open(encoding="ascii") as trace:
        match = re.fullmatch(
            r"# timbre_bank v1 A=(\d+) D=(\d+) S=(\d+) R=(\d+) SHIFT=(\d+)",
            trace.readline().strip(),
        )
        if not match or tuple(map(int, match.groups())) != CONFIGURATIONS[name]:
            raise AssertionError(f"{path}: missing or unexpected configuration")
        a, d, s, r, shift = CONFIGURATIONS[name]
        a, d, s, r = max(a, 1), max(d, 1), min(s, 65536), max(r, 1)

        def reset_state():
            envs = [Envelope() for _ in range(4)]
            for env in envs:
                env.ATTACK, env.DECAY, env.SUSTAIN, env.RELEASE = a, d, s, r
            return (envs, [0]*4, [0]*4, [None]*4,
                    None, None, None, [0]*4, [0]*4, [False]*4, 0)

        (envs, phases, colors, event_colors, raw_q, voice_q, gain_q,
         voice_values, gain_values, mixed_nonzero, sample) = reset_state()
        clocks = samples = resets = positive = negative = positive_clip = negative_clip = 0
        coverage = dict(soft=0, bright=0, deferred=0, replaced=0, override=0,
                        held=0, tail=0, fallback=0, mixed=0, discarded=0,
                        zero_sustain_hold=0)
        seen_colors = [set() for _ in range(4)]
        footer = None
        for line in trace:
            if line.startswith("# completed "):
                footer = line.strip()
                if trace.read().strip():
                    raise AssertionError("Data after completion footer")
                break
            fields = list(map(int, line.split()))
            if len(fields) != 18:
                raise AssertionError("Malformed clock record: expected 18 integers")
            reset_n, request, gates, triggers, notes, velocities, selected = fields[:7]
            observed = tuple(fields[7:])
            if reset_n not in (0, 1) or request not in (0, 1):
                raise AssertionError("Non-binary reset/request")
            if not (0 <= gates < 16 and 0 <= triggers < 16 and 0 <= selected < 16
                    and 0 <= notes < 2**28 and 0 <= velocities < 2**28):
                raise AssertionError("Control field outside its declared bit width")
            clocks += 1
            clip = False
            if not reset_n:
                (envs, phases, colors, event_colors, raw_q, voice_q, gain_q,
                 voice_values, gain_values, mixed_nonzero, sample) = reset_state()
                valid, active, released, sounding = False, 0, 15, False
                resets += 1
            else:
                # 三个时钟间隔：ROM/env -> ADSR gain -> velocity gain -> mix。
                valid = gain_q is not None
                if valid:
                    shifted = sum(gain_q) // 2**shift
                    clip = not -32768 <= shifted <= 32767
                    sample = max(-32768, min(32767, shifted))
                    mixed_nonzero = [value != 0 for value in gain_q]
                next_gain = None if voice_q is None else [
                    value * (65536 if velocity == 127 else velocity * 512) // 65536
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
                    gate, trigger, color = (gates >> v) & 1, (triggers >> v) & 1, (selected >> v) & 1
                    if request:
                        new_note = bool(gate and (trigger or env.pending or not env.gate or env.state == 0))
                        if new_note:
                            if trigger:
                                coverage["override"] += event_colors[v] is not None
                                colors[v] = color
                            elif event_colors[v] is not None:
                                coverage["deferred"] += 1
                                colors[v] = event_colors[v]
                            else:
                                colors[v] = color
                            coverage["bright" if colors[v] else "soft"] += 1
                            seen_colors[v].add(colors[v])
                        elif color != colors[v]:
                            coverage["held"] += bool(gate)
                            coverage["tail"] += not gate and env.level != 0
                            coverage["zero_sustain_hold"] += bool(gate and env.state == 3 and env.level == 0)
                        coverage["discarded"] += not gate and event_colors[v] is not None
                        event_colors[v] = None
                    elif trigger:
                        coverage["replaced"] += event_colors[v] is not None
                        event_colors[v] = color
                    env.clock(request, gate, trigger)
                    if request:
                        note = (notes >> (7*v)) & 127
                        velocity = (velocities >> (7*v)) & 127
                        increment = math.floor(440 * 2**((note-69)/12) * 2**32 / 48000 + 0.5)
                        coverage["fallback"] += bool(colors[v] and increment >= 2**29 and env.level)
                        next_raw.append((oscillator(phases[v], colors[v], increment) * env.level // 65536,
                                         velocity))
                        phases[v] = (phases[v] + increment) % 2**32
                    busy = (gate or env.state != 0 or
                            (next_voice is not None and voice_values[v] != 0) or
                            (next_gain is not None and gain_values[v] != 0) or mixed_nonzero[v])
                    active |= int(bool(busy)) << v
                    released |= int(not gate and not busy) << v
                coverage["mixed"] += bool(request and gates == 15 and any(colors) and not all(colors))
                raw_q, voice_q, gain_q = next_raw if request else None, next_voice, next_gain
                sounding = bool(active)
            adopted = sum(color << v for v, color in enumerate(colors))
            expected = (sample, int(valid), int(clip), active, released, int(sounding),
                        *(env.level for env in envs), adopted)
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
        if clocks < 7000 or samples < 2000 or resets < 4 or not (positive and negative):
            raise AssertionError("Missing clock/sample/reset/signed coverage")
        missing = [key for key, count in coverage.items() if not count and key != "zero_sustain_hold"]
        if missing or seen_colors != [{0, 1} for _ in range(4)]:
            raise AssertionError(f"Missing adoption coverage {missing}, per voice colors={seen_colors}")
        if name == "zero" and not coverage["zero_sustain_hold"]:
            raise AssertionError("Missing zero-sustain held-note timbre retention")
        if shift and (positive_clip or negative_clip):
            raise AssertionError("Quiet mix should not saturate")
        if not shift and not (positive_clip and negative_clip):
            raise AssertionError("Missing both signs of saturation")
        if sample != 0 or active != 0 or released != 15 or any(env.level for env in envs):
            raise AssertionError("Final tails are not drained")
        print(f"PASS Python timbre bank {name}: {clocks} clocks, {samples} samples, {resets} resets, "
              f"clips +{positive_clip}/-{negative_clip}; coverage={coverage}.")


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    for name in CONFIGURATIONS:
        parser.add_argument(f"--{name}-trace", type=Path,
                            default=root / f"build/regression/logs/timbre_bank_{name}_trace.txt")
    args = parser.parse_args()
    for name in CONFIGURATIONS:
        check_trace(getattr(args, f"{name}_trace"), name)


if __name__ == "__main__":
    main()
