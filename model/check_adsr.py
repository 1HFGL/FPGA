"""Independently verify the exported voice_adsr trace (Python standard library)."""
import argparse
import math
from pathlib import Path


class Envelope:
    """按段起点/已走采样数计算直线，不照搬 RTL 余数累加器。"""

    ATTACK, DECAY, SUSTAIN, RELEASE = 96, 24000, 6554, 5760

    def __init__(self):
        self.level = 0
        self.state = 0
        self.gate = False
        self.pending = False
        self.segment = None
        self.start = 0
        self.age = 0

    def ramp(self, name, start_new=False):
        if start_new or self.segment != name:
            self.segment, self.start, self.age = name, self.level, 0
        self.age += 1
        if name == "attack":
            self.level = self.start + (65536 - self.start) * self.age // self.ATTACK
            self.state = 2 if self.age == self.ATTACK else 1
        elif name == "decay":
            self.level = self.start - (self.start - self.SUSTAIN) * self.age // self.DECAY
            self.state = 3 if self.age == self.DECAY else 2
        else:
            self.level = self.start - self.start * self.age // self.RELEASE
            self.state = 0 if self.age == self.RELEASE else 4

    def clock(self, tick, gate, retrigger):
        if not tick:
            self.pending |= bool(retrigger)
            return
        new_note = retrigger or self.pending or not self.gate or self.state == 0
        if not gate:
            if self.level == 0:
                self.state, self.segment = 0, None
            else:
                self.ramp("release")
        elif new_note or self.state == 1:
            self.ramp("attack", start_new=bool(new_note))
        elif self.state == 2:
            self.ramp("decay")
        else:
            self.level, self.state, self.segment = self.SUSTAIN, 3, None
        self.gate, self.pending = bool(gate), False


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path, default=root / "build/regression/logs/adsr_trace.txt")
    args = parser.parse_args()
    envelope = Envelope()
    phase = 0
    queued = None
    sample = 0
    samples = resets = clocks = 0
    seen_states = set()
    completed = {"attack": set(), "decay": set(), "release": set()}
    positive = negative = False
    with args.trace.open(encoding="ascii") as trace:
        for clocks, line in enumerate(trace, 1):
            rst, tick, gate, retrigger, inc, actual, valid, level, active, state = map(int, line.split())
            if rst:
                envelope, phase, queued, sample = Envelope(), 0, None, 0
                expected_valid = False
                resets += 1
            else:
                expected_valid = queued is not None
                if expected_valid:
                    sample = queued
                envelope.clock(tick, gate, retrigger)
                if tick and envelope.segment:
                    target = {"attack": 2, "decay": 3, "release": 0}[envelope.segment]
                    if envelope.state == target:
                        completed[envelope.segment].add(envelope.age)
                if tick:
                    value = 32767 * math.sin(2 * math.pi * (phase >> 22) / 1024)
                    raw = math.floor(value + .5) if value >= 0 else math.ceil(value - .5)
                    queued = raw * envelope.level // 65536
                    phase = (phase + inc) % (1 << 32)
                else:
                    queued = None
            expected_active = envelope.state != 0 or (expected_valid and sample != 0)
            expected = (sample, int(expected_valid), envelope.level, int(expected_active), envelope.state)
            observed = (actual, valid, level, active, state)
            if observed != expected:
                raise AssertionError(f"Clock {clocks}: actual {observed}, expected {expected}")
            seen_states.add(state)
            if valid:
                samples += 1
                positive |= sample > 0
                negative |= sample < 0
    if clocks < 100000 or samples < 40000 or resets < 3 or seen_states != set(range(5)):
        raise AssertionError("Incomplete trace or missing stage/reset coverage")
    if completed != {"attack": {96}, "decay": {24000}, "release": {5760}}:
        raise AssertionError(f"Missing or incorrect completed stage durations: {completed}")
    if not (positive and negative) or sample != 0 or envelope.state != 0:
        raise AssertionError("Missing signed output coverage or final silence")
    print(f"PASS Python ADSR reference: {clocks} clocks, {samples} samples, {resets} resets, all 5 states; A/D/R = 96/24000/5760 samples.")


if __name__ == "__main__":
    main()
