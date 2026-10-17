"""电脑端识别板键双预设固件；不打开真实COM，不修改队友现有测试。"""
import os
from pathlib import Path
import sys
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "host"))
from PySide6.QtWidgets import QApplication
from studio_transport import StudioSession
from test_studio import SilentTransport


class DualHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.session = StudioSession()
        self.device = SilentTransport()
        self.session.connect_device("test", transport=self.device)

    def tearDown(self):
        self.session.disconnect_device()
        QApplication.processEvents()

    def hello(self, tone="PIANO_GUITAR", caps="NOTES,STATUS"):
        self.device.line.emit(f"SYNTH/1 CAPS={caps} MAX_VOICES=16 SAMPLE_RATE=48000 FW=uart-dual-v1 TONE={tone}")

    def test_dual_firmware_can_play_without_apply(self):
        self.hello()
        self.assertTrue(self.session.playable)
        self.assertEqual(self.session.fixed_tone_name, "钢琴／吉他（KEY2切换）")
        self.session.note(60, True)
        self.session.note(60, False)
        self.assertEqual(self.device.commands[-2:], ["NOTE_ON 60 100 0", "NOTE_OFF 60 0"])
        self.assertIsNone(self.session.applied)

    def test_unknown_tone_stays_blocked(self):
        self.hello("PIANO_GUITAR_UNKNOWN")
        self.assertFalse(self.session.playable)

    def test_config_device_still_requires_apply(self):
        self.hello(caps="CONFIG,NOTES,STATUS")
        self.assertFalse(self.session.fixed_tone)
        self.assertFalse(self.session.playable)

    def test_status_keeps_shared_capacity(self):
        self.hello()
        self.device.line.emit("STATUS VOICE_COUNT=2 MAX_VOICE_COUNT=16 STEAL_COUNT=1 SAMPLE_RATE=48000")
        self.assertEqual(self.session.device["MAX_VOICES"], "16")
        self.assertEqual(self.session.status["VOICE_COUNT"], 2)
        self.assertTrue(self.session.playable)


if __name__ == "__main__":
    unittest.main()
