"""钢琴感配置/单周期波表合同；不是实物声音或音质证明。"""
import math
from pathlib import Path
import unittest

from studio_model import cycle_samples, load_tone

ROOT = Path(__file__).resolve().parents[1]


class PianoPresetTests(unittest.TestCase):
    def test_preset_and_rom_match(self):
        tone = load_tone(ROOT / "fpga_music_tool/tone_examples/piano.json")
        self.assertEqual((tone.attack_ms, tone.decay_ms, tone.sustain, tone.release_ms), (2, 1200, 0, 180))
        self.assertEqual(tone.vibrato_cents, 0)
        values = [int(line, 16) for line in (ROOT / "rtl/rom/piano_1024.mem").read_text().splitlines()]
        values = [x if x < 32768 else x - 65536 for x in values]
        self.assertEqual(values, [round(x * 32767) for x in cycle_samples(tone)])
        self.assertEqual(len(values), 1024)
        self.assertEqual(max(values), 32767)
        self.assertEqual(min(values), -32767)
        self.assertEqual(sum(values), 0)
        # 单周期DFT验证基音与新增谐波；并非把谐波算作复音。
        amplitudes = [2 * abs(sum(x * math.sin(2 * math.pi * h * n / 1024)
                                  for n, x in enumerate(values))) / 1024 for h in range(1, 17)]
        self.assertGreater(amplitudes[0], amplitudes[1])
        for h in range(2, 9):
            self.assertAlmostEqual(amplitudes[h-1] / amplitudes[0], tone.harmonics[h-1] / 255, places=4)
        self.assertLess(max(amplitudes[8:]), 0.1)


if __name__ == "__main__":
    unittest.main()
