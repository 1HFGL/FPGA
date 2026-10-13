"""Run: python -m unittest discover -s host -p test_studio.py -v.

These checks establish PC behaviour only, not FPGA or physical audio behaviour.
"""
import copy
import json
import math
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QObject, Qt, Signal
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from studio_model import (Tone, apply_command, crc16, cycle_samples, decode_apply,
                          export_hex, harmonic_preset, load_tone, save_tone)
from studio_transport import LineDecoder, MockTransport, SerialTransport, StudioSession
from studio import StudioWindow, configure_fonts


def wait_for(predicate, milliseconds=1200):
    deadline = time.monotonic() + milliseconds / 1000
    while time.monotonic() < deadline:
        QApplication.processEvents()
        if predicate():
            return
        QTest.qWait(10)
    raise AssertionError("Timed out waiting for the expected state")


class ModelTests(unittest.TestCase):
    def test_unicode_roundtrip_and_invalid_load(self):
        tone = Tone(name="笛声 · 柔和", harmonics=harmonic_preset("soft"), attack_ms=0, release_ms=10000)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "音色.json"
            save_tone(path, tone)
            self.assertEqual(load_tone(path), tone)
            path.write_text('{"version":999}', encoding="utf-8")
            with self.assertRaises(ValueError):
                load_tone(path)

    def test_reject_invalid_types_ranges_and_missing_fields(self):
        for key, value in [("volume", True), ("sustain", 256), ("attack_ms", -1),
                           ("harmonics", [255] * 15), ("harmonics", [0] * 15 + [1.5]),
                           ("mode", 3), ("name", "  ")]:
            data = Tone().document()
            data["tone"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                Tone.from_document(data)
        data = Tone().document()
        del data["tone"]["volume"]
        with self.assertRaises(ValueError):
            Tone.from_document(data)

    def test_failed_save_preserves_original_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tone.json"
            save_tone(path, Tone())
            before = path.read_bytes()
            with patch("studio_model.os.replace", side_effect=OSError("disk error")):
                with self.assertRaises(OSError):
                    save_tone(path, Tone(name="another"))
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

    def test_crc_known_vector_and_wire_roundtrip(self):
        self.assertEqual(crc16("123456789"), 0x29b1)
        tone = Tone(harmonics=harmonic_preset("bright"), volume=255, mode=2, vibrato_cents=100)
        sequence, received = decode_apply(apply_command(123, tone))
        self.assertEqual(sequence, 123)
        self.assertEqual(received.fingerprint(), tone.fingerprint())

    def test_corrupt_packet_and_illegal_values_rejected(self):
        line = apply_command(2, Tone())
        with self.assertRaises(ValueError):
            decode_apply(line.replace("255,", "254,", 1))
        for line in ["APPLY 2 255,0", "APPLY 1 invalid 0000"]:
            with self.assertRaises(ValueError):
                decode_apply(line)

    def test_single_cycle_sine_extrema_zero_and_harmonics(self):
        tone = Tone()
        samples = cycle_samples(tone)
        self.assertAlmostEqual(samples[0], 0)
        self.assertAlmostEqual(samples[256], 1)
        self.assertAlmostEqual(samples[768], -1)
        self.assertAlmostEqual(sum(samples), 0, places=9)
        self.assertEqual(cycle_samples(Tone(harmonics=[0] * 16)), [0.] * 1024)
        samples = cycle_samples(Tone(harmonics=[0, 255] + [0] * 14))
        fundamental = sum(x * math.sin(2 * math.pi * n / 1024) for n, x in enumerate(samples))
        second = sum(x * math.sin(4 * math.pi * n / 1024) for n, x in enumerate(samples))
        self.assertAlmostEqual(fundamental, 0, places=8)
        self.assertAlmostEqual(second, 512, places=8)

    def test_hex_has_exactly_one_cycle_and_signed_extrema(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tone.hex"
            export_hex(path, Tone())
            words = path.read_text(encoding="ascii").splitlines()
            self.assertEqual(len(words), 1024)
            self.assertEqual(words[0], "0000")
            self.assertEqual(words[256], "7FFF")
            self.assertEqual(words[768], "8001")

    def test_copy_does_not_alias_harmonics(self):
        tone = Tone()
        other = tone.copy()
        other.harmonics[0] = 1
        self.assertEqual(tone.harmonics[0], 255)


class SilentTransport(QObject):
    opened = Signal()
    line = Signal(str)
    error = Signal(str)
    closed = Signal()
    traffic = Signal(int, int)

    def __init__(self):
        super().__init__()
        self.commands = []

    def start(self):
        self.opened.emit()

    def send(self, line):
        self.commands.append(line)

    def close(self):
        self.closed.emit()


class QtTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        cls.app.setStyle("Fusion")
        configure_fonts()

    def setUp(self):
        self.session = StudioSession()

    def tearDown(self):
        self.session.disconnect_device()
        QApplication.processEvents()

    def connect_mock(self):
        self.session.connect_device("SIM")
        wait_for(lambda: self.session.ready)

    def test_split_overlong_and_invalid_lines_resynchronize(self):
        decoder = LineDecoder()
        self.assertEqual(decoder.feed(b"SYNTH/"), [])
        self.assertEqual(decoder.feed(b"1 X=1\r\nSTATUS V=0\n"), ["SYNTH/1 X=1", "STATUS V=0"])
        self.assertEqual(decoder.feed(b"x" * 600 + b"\n\xff\nA\x00B\nOK\n"), ["OK"])
        self.assertEqual(len(decoder.buffer), 0)

    def test_serial_open_alone_never_enables_apply(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        self.assertEqual(device.commands, ["HELLO"])
        self.session._handshake_timeout()
        self.assertFalse(self.session.ready)
        with self.assertRaises(RuntimeError):
            self.session.apply(Tone())
        self.assertIsNone(self.session.applied)

    def test_fixed_sine_device_plays_without_fake_apply(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE")
        self.session.note(60, True)
        self.session.note(60, False)
        self.assertEqual(device.commands[-2:], ["NOTE_ON 60 100 0", "NOTE_OFF 60 0"])
        self.assertIsNone(self.session.applied)
        with self.assertRaises(RuntimeError):
            self.session.apply(Tone())
        self.session.disconnect_device()
        self.assertEqual(device.commands[-1], "PANIC")

    def test_unknown_fixed_device_cannot_bypass_apply(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000")
        with self.assertRaises(RuntimeError):
            self.session.note(60, True)

    def test_fixed_piano_device_plays_without_fake_apply(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-piano-v1 TONE=FIXED_PIANO")
        self.assertTrue(self.session.fixed_tone)
        self.assertFalse(self.session.fixed_sine)
        self.assertEqual(self.session.fixed_tone_name, "钢琴感")
        self.session.note(72, True)
        self.session.note(72, False)
        self.assertEqual(device.commands[-2:], ["NOTE_ON 72 100 0", "NOTE_OFF 72 0"])
        self.assertIsNone(self.session.applied)
        with self.assertRaises(RuntimeError):
            self.session.apply(Tone())

    def test_unknown_tone_does_not_enable_fixed_playback(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 TONE=FIXED_UNKNOWN")
        self.assertFalse(self.session.playable)

    def test_fixed_device_not_ready_requires_reconnect(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 TONE=FIXED_SINE")
        self.assertTrue(self.session.playable)
        device.line.emit("ERROR 0 NOT_READY")
        self.assertFalse(self.session.ready)
        self.assertFalse(self.session.playable)
        self.assertFalse(self.session.poll.isActive())

    def test_malformed_or_wrong_version_handshake_is_rejected(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        for line in ["SYNTH/2 CAPS=CONFIG", "SYNTH/1 CAPS=CONFIG MAX_VOICES=0 SAMPLE_RATE=48000"]:
            device.line.emit(line)
            self.assertFalse(self.session.ready)
        device.line.emit("SYNTH/1 CAPS=STATUS MAX_VOICES=4 SAMPLE_RATE=48000")
        self.assertTrue(self.session.ready)
        with self.assertRaises(RuntimeError):
            self.session.apply(Tone())

    def test_apply_snapshot_ack_and_duplicate_protection(self):
        self.connect_mock()
        tone = Tone()
        self.session.apply(tone)
        tone.volume = 100
        with self.assertRaises(RuntimeError):
            self.session.apply(tone)
        wait_for(lambda: self.session.applied is not None)
        self.assertEqual(self.session.applied.volume, 64)
        self.assertNotEqual(self.session.applied.fingerprint(), tone.fingerprint())
        self.session.transport.line.emit("APPLIED 999")
        self.assertEqual(self.session.applied.volume, 64)

    def test_timeout_never_claims_applied_and_late_ack_ignored(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=CONFIG MAX_VOICES=4 SAMPLE_RATE=48000")
        self.session.apply(Tone())
        device.line.emit("APPLIED 999")
        self.assertIsNotNone(self.session.pending)
        self.session._apply_timeout()
        device.line.emit("APPLIED 1")
        self.assertIsNone(self.session.applied)

    def test_negative_reply_and_disconnect_clear_device_state(self):
        device = SilentTransport()
        self.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=CONFIG MAX_VOICES=4 SAMPLE_RATE=48000")
        self.session.apply(Tone())
        device.line.emit("ERROR 1 BAD_CRC")
        self.assertIsNone(self.session.pending)
        self.assertIsNone(self.session.applied)
        self.session.disconnect_device()
        self.assertFalse(self.session.ready)
        self.assertEqual(self.session.capabilities, set())

    def test_simulated_polyphony_steal_and_panic(self):
        self.connect_mock()
        self.session.apply(Tone())
        wait_for(lambda: self.session.applied is not None)
        for note in [60, 64, 67, 72, 74]:
            self.session.note(note, True)
        wait_for(lambda: self.session.status.get("STEAL_COUNT") == 1)
        self.assertEqual(self.session.status["VOICE_COUNT"], 4)
        self.session.note(74, False)
        wait_for(lambda: self.session.status.get("VOICE_COUNT") == 3)
        self.session.panic()
        wait_for(lambda: self.session.status.get("VOICE_COUNT") == 0)

    def test_reconnect_drops_late_old_transport_reply(self):
        self.connect_mock()
        old = self.session.transport
        self.session.apply(Tone())
        self.session.disconnect_device()
        self.connect_mock()
        self.assertIsNone(self.session.applied)
        self.assertFalse(old.running)

    def test_mock_replies_preserve_uart_order(self):
        device = MockTransport()
        received = []
        device.line.connect(received.append)
        device.start()
        for n in range(8):
            device.reply(f"packet {n}")
        wait_for(lambda: len(received) == 8)
        self.assertEqual(received, [f"packet {n}" for n in range(8)])
        device.close()

    def test_serial_worker_runs_fragmented_io_and_shutdown(self):
        class MemoryPort:
            in_waiting = 3
            def __init__(self, *args, **kwargs):
                self.data = bytearray()
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def write(self, payload):
                self.data.extend(b"SYNTH/1 CAPS=CONFIG MAX_VOICES=4 SAMPLE_RATE=48000\n")
                return len(payload)
            def read(self, count):
                result = bytes(self.data[:count])
                del self.data[:count]
                time.sleep(.002)
                return result
        device = SerialTransport("test", 115200)
        with patch("serial.Serial", MemoryPort):
            self.session.connect_device("test", transport=device)
            wait_for(lambda: self.session.ready)
            self.assertGreater(self.session.rx_bytes, 0)
            self.session.disconnect_device()
            self.assertFalse(device.isRunning())


class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        configure_fonts()

    def setUp(self):
        self.window = StudioWindow()
        self.window.test_mode = True
        self.window.show()
        QApplication.processEvents()

    def tearDown(self):
        self.window.close()
        QApplication.processEvents()

    def test_harmonic_keyboard_mouse_and_zero_preview(self):
        window = self.window
        editor = window.harmonics
        QTest.keyClick(editor, Qt.Key_Right)
        QTest.keyClick(editor, Qt.Key_Up, Qt.ShiftModifier)
        self.assertEqual(window.tone.harmonics[1], 8)
        rect = editor.plot_rect()
        point = rect.center().toPoint()
        QTest.mouseClick(editor, Qt.LeftButton, pos=point)
        self.assertTrue(100 <= window.tone.harmonics[editor.index] <= 155)
        window.set_harmonics("zero")
        self.assertEqual(window.tone.harmonics, [0] * 16)
        self.assertFalse(window.grab().isNull())

    def test_fixed_sine_gui_enables_keys_not_parameters(self):
        window = self.window
        device = SilentTransport()
        window.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE")
        self.assertTrue(window.chord_button.isEnabled())
        self.assertTrue(all(key.isEnabled() for key in window.piano_buttons))
        self.assertFalse(window.apply_button.isEnabled())
        self.assertIn("固定正弦", window.document_label.text())
        self.assertIsNone(window.session.applied)
        window.chord()
        self.assertEqual(window.pressed_notes, {60, 64, 67, 72})
        window.session.disconnect_device()
        self.assertFalse(window.pressed_notes)

    def test_fixed_piano_gui_labels_real_tone_not_draft(self):
        window = self.window
        device = SilentTransport()
        window.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-piano-v1 TONE=FIXED_PIANO")
        self.assertTrue(window.chord_button.isEnabled())
        self.assertFalse(window.apply_button.isEnabled())
        self.assertIn("固定钢琴感", window.document_label.text())
        self.assertIn("固定钢琴感", window.play_hint.text())
        self.assertIsNone(window.session.applied)
        window.edit_harmonic(0, 0)
        self.assertIn("界面参数未应用", window.document_label.text())
        self.assertFalse(window.apply_button.isEnabled())

    def test_save_load_and_invalid_load_preserve_draft(self):
        window = self.window
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tone.json"
            window.tone.name = "测试笛声"
            self.assertTrue(window.save_to(path))
            self.assertFalse(window.dirty())
            window.edit_harmonic(2, 99)
            self.assertTrue(window.dirty())
            self.assertTrue(window.load_from(path))
            self.assertEqual(window.tone.harmonics[2], 0)
            before = window.tone.copy()
            path.write_text("invalid json", encoding="utf-8")
            self.assertFalse(window.load_from(path))
            self.assertEqual(window.tone, before)

    def test_visible_confirmation_and_edit_while_pending(self):
        window = self.window
        self.assertFalse(window.apply_button.isEnabled())
        window.toggle_connection()
        wait_for(lambda: window.session.ready)
        self.assertTrue(window.apply_button.isEnabled())
        window.apply()
        window.parameter_changed("volume", 100)
        wait_for(lambda: window.session.applied is not None)
        self.assertIn("与草稿不一致", window.document_label.text())
        window.apply()
        wait_for(lambda: window.session.pending is None)
        self.assertIn("模拟设备已确认", window.document_label.text())
        window.navigate(1)
        window.chord()
        wait_for(lambda: window.session.status.get("VOICE_COUNT") == 4)
        window.navigate(2)
        wait_for(lambda: window.session.status.get("VOICE_COUNT") == 0)

    def test_empty_name_is_editable_but_cannot_apply(self):
        window = self.window
        window.name_changed("")
        window.parameter_changed("volume", 128)
        window.edit_harmonic(1, 20)
        self.assertFalse(window.apply_button.isEnabled())
        self.assertFalse(window.grab().isNull())

    def test_parameter_sliders_and_numeric_fields_stay_in_sync(self):
        window = self.window
        window.parameter_sliders["attack_ms"].setValue(850)
        self.assertEqual(window.tone.attack_ms, 850)
        self.assertEqual(window.parameter_spins["attack_ms"].value(), 850)
        window.parameter_spins["sustain"].setValue(0)
        self.assertEqual(window.parameter_sliders["sustain"].value(), 0)
        self.assertEqual(window.tone.sustain, 0)
        window.set_harmonics("bright")
        self.assertEqual(window.harmonic_count.text(), "08 / 16 启用")

    def test_overlaid_black_key_mouse_press_and_release(self):
        window = self.window
        window.toggle_connection()
        wait_for(lambda: window.session.ready)
        window.apply()
        wait_for(lambda: window.session.applied is not None)
        window.navigate(1)
        QApplication.processEvents()
        white, black = window.piano_buttons[:2]
        self.assertLess(black.height(), white.height())
        self.assertLess(black.x(), white.geometry().right())
        self.assertGreater(black.geometry().right(), white.geometry().right())
        QTest.mousePress(black, Qt.LeftButton, pos=black.rect().center())
        self.assertIn(61, window.pressed_notes)
        wait_for(lambda: window.session.status.get("VOICE_COUNT") == 1)
        QTest.mouseRelease(black, Qt.LeftButton, pos=black.rect().center())
        self.assertNotIn(61, window.pressed_notes)
        wait_for(lambda: window.session.status.get("VOICE_COUNT") == 0)


if __name__ == "__main__":
    unittest.main()
