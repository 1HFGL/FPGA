"""Independently verify the exported voice_adsr trace (Python standard library)."""
import argparse
import math
from pathlib import Path


class Envelope:
    """Piecewise lines evaluated from a segment's start level and elapsed ticks."""

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
            self.level = min(65536, self.start + 137 * self.age)
            self.state = 2 if self.level == 65536 else 1
        elif name == "decay":
            self.level = max(32768, self.start - 7 * self.age)
            self.state = 3 if self.level == 32768 else 2
        else:
            self.level = max(0, self.start - 3 * self.age)
            self.state = 0 if self.level == 0 else 4

    def clock(self, tick, gate, retrigger):
        if not tick:
            self.pending |= bool(retrigger)
            return
        new_note = retrigger or self.pending or not self.gate or self.state == 0
        if not gate:
            self.ramp("release")
        elif new_note or self.state == 1:
            self.ramp("attack", start_new=bool(new_note))
        elif self.state == 2:
            self.ramp("decay")
        else:
            self.level, self.state, self.segment = 32768, 3, None
        self.gate, self.pending = bool(gate), False


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path, default=root / "results/logs/adsr_trace.txt")
    args = parser.parse_args()
    envelope = Envelope()
    phase = 0
    queued = None
    sample = 0
    samples = resets = clocks = 0
    seen_states = set()
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
    if not (positive and negative) or sample != 0 or envelope.state != 0:
        raise AssertionError("Missing signed output coverage or final silence")
    print(f"PASS Python ADSR reference: {clocks} clocks, {samples} samples, {resets} resets, all 5 states.")


if __name__ == "__main__":
    main()
