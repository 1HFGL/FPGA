"""Current host regressions. No real serial port or FPGA is opened."""
import os
import queue
import time
import unittest
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import Qt
from PySide6.QtTest import QTest
from PySide6.QtGui import QKeyEvent
from PySide6.QtCore import QEvent
from PySide6.QtWidgets import QApplication

from studio import StudioWindow, configure_fonts
from studio_model import Tone
from studio_transport import SerialTransport, StudioSession
from test_studio import SilentTransport, wait_for


class PerformanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        configure_fonts()

    def setUp(self):
        self.session = StudioSession()
        self.device = SilentTransport()
        self.session.connect_device("test", transport=self.device)

    def tearDown(self):
        self.session.disconnect_device()
        QApplication.processEvents()

    def fixed(self, voices=16):
        self.device.line.emit(f"SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES={voices} SAMPLE_RATE=48000 FW=test TONE=FIXED_PIANO")

    def test_release_is_permitted_without_confirmed_configuration(self):
        self.device.line.emit("SYNTH/1 CAPS=CONFIG,NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000")
        self.session.note(60, False)
        self.assertEqual(self.device.commands[-1], "NOTE_OFF 60 0")

    def test_pending_configuration_blocks_new_notes_and_timeout_stops(self):
        self.device.line.emit("SYNTH/1 CAPS=CONFIG,NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000")
        self.session.apply(Tone())
        self.device.line.emit("APPLIED 1")
        self.session.note(60, True)
        self.session.apply(Tone(volume=100))
        self.assertFalse(self.session.playable)
        with self.assertRaises(RuntimeError):
            self.session.note(64, True)
        self.session._apply_timeout()
        self.assertEqual(self.device.commands[-1], "PANIC")
        self.assertFalse(self.session.active_notes)

    def test_failed_release_is_retained_and_retried(self):
        self.fixed()
        self.session.note(60, True)
        with patch.object(self.device, "send", side_effect=RuntimeError("full")):
            with self.assertRaises(RuntimeError):
                self.session.note(60, False)
            self.assertIn(60, self.session.active_notes)
        wait_for(lambda: not self.session.active_notes)
        self.assertEqual(self.device.commands[-1], "NOTE_OFF 60 0")

    def test_failed_panic_retries_and_blocks_new_notes(self):
        self.fixed()
        self.session.note(60, True)
        with patch.object(self.device, "send", side_effect=RuntimeError("full")):
            with self.assertRaises(RuntimeError):
                self.session.panic()
            self.assertFalse(self.session.playable)
        wait_for(lambda: not self.session.active_notes and self.session.playable)
        self.assertEqual(self.device.commands[-1], "PANIC")

    def test_status_timeout_invalidates_session_without_replaying_notes(self):
        self.fixed()
        self.session.note(60, True)
        self.session.last_response = time.monotonic() - 4
        self.session.query_status()
        self.assertFalse(self.session.ready)
        self.assertFalse(self.session.poll.isActive())
        self.assertIn("PANIC", self.device.commands)

    def test_status_ranges_and_real_capacity_are_not_invented(self):
        self.fixed(4)
        self.device.line.emit("STATUS VOICE_COUNT=16 MAX_VOICE_COUNT=16 STEAL_COUNT=1 SAMPLE_RATE=48000")
        self.assertEqual(self.session.device["MAX_VOICES"], "4")
        self.assertEqual(self.session.status["VOICE_COUNT"], 16)
        self.device.line.emit("STATUS VOICE_COUNT=99 SAMPLE_RATE=0 STEAL_COUNT=-1")
        self.assertEqual(self.session.status["VOICE_COUNT"], 16)
        self.assertEqual(self.session.status["SAMPLE_RATE"], 48000)

    def test_piano_simulator_has_sixteen_voices_without_apply(self):
        self.session.disconnect_device()
        self.session.connect_device("SIM_PIANO")
        wait_for(lambda: self.session.ready)
        self.assertEqual(self.session.device["MAX_VOICES"], "16")
        self.assertTrue(self.session.playable)
        self.assertNotIn("CONFIG", self.session.capabilities)
        for note in range(48, 65):
            self.session.note(note, True)
        self.session.query_status()
        wait_for(lambda: self.session.status.get("STEAL_COUNT") == 1)
        self.assertEqual(self.session.status["VOICE_COUNT"], 16)
        self.session.panic()
        wait_for(lambda: self.session.status.get("VOICE_COUNT") == 0)

    def test_stop_commands_have_space_and_cancel_unsent_note_ons(self):
        worker = SerialTransport("NOT_OPENED", 115200)
        for _ in range(64):
            worker.send("STATUS?")
        with self.assertRaises(RuntimeError):
            worker.send("NOTE_ON 60 100 0")
        worker.send("NOTE_OFF 60 0")
        self.assertEqual(worker.outbound.get_nowait(), b"NOTE_OFF 60 0\n")
        worker.send("PANIC")
        self.assertEqual(worker.outbound.get_nowait(), b"PANIC\n")
        second = SerialTransport("NOT_OPENED", 115200)
        second.send("NOTE_ON 60 100 0")
        second.send("NOTE_OFF 60 0")
        self.assertEqual(second.outbound.get_nowait(), b"NOTE_OFF 60 0\n")
        with self.assertRaises(queue.Empty):
            second.outbound.get_nowait()

    def test_stop_priority_does_not_replay_old_notes_or_cancel_future_notes(self):
        worker = SerialTransport("NOT_OPENED", 115200)
        worker.send("NOTE_ON 60 100 0")
        worker.send("NOTE_OFF 60 0")
        worker.send("NOTE_ON 60 100 0")
        self.assertEqual(worker.outbound.get_nowait(), b"NOTE_OFF 60 0\n")
        self.assertEqual(worker.outbound.get_nowait(), b"NOTE_ON 60 100 0\n")
        worker.send("NOTE_ON 64 100 0")
        worker.send("NOTE_OFF 67 0")
        worker.send("PANIC")
        self.assertEqual(worker.outbound.get_nowait(), b"PANIC\n")
        with self.assertRaises(queue.Empty):
            worker.outbound.get_nowait()

    def test_pitch_cannot_retrigger_until_failed_release_is_sent(self):
        self.fixed()
        self.session.note(60, True)
        with patch.object(self.device, "send", side_effect=RuntimeError("full")):
            with self.assertRaises(RuntimeError):
                self.session.note(60, False)
        with self.assertRaises(RuntimeError):
            self.session.note(60, True)
        wait_for(lambda: not self.session.pending_releases)
        self.session.note(60, True)
        self.assertIn(60, self.session.active_notes)

    def test_serial_chord_does_not_wait_for_unsolicited_replies(self):
        writes = []
        class Port:
            in_waiting = 0
            def __init__(self, *args, **kwargs): self.timeout = kwargs["timeout"]
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def write(self, payload):
                writes.append(time.monotonic())
                return len(payload)
            def read(self, count):
                time.sleep(self.timeout)
                return b""
        worker = SerialTransport("NOT_OPENED", 115200)
        for note in [60, 64, 67, 72]: worker.send(f"NOTE_ON {note} 100 0")
        with patch("serial.Serial", Port):
            worker.start()
            try:
                wait_for(lambda: len(writes) == 4)
            finally:
                worker.close()
        self.assertLess(writes[-1] - writes[0], .06)


class PerformanceGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        configure_fonts()

    def setUp(self):
        self.window = StudioWindow()
        self.window.test_mode = True
        self.window.show()
        self.window.toggle_connection()
        wait_for(lambda: self.window.session.ready)

    def tearDown(self):
        self.window.close()
        QApplication.processEvents()

    def test_default_home_is_playable_piano_and_clean_draft(self):
        w = self.window
        self.assertEqual(w.pages.currentIndex(), 1)
        self.assertTrue(w.session.playable)
        self.assertFalse(w.apply_button.isEnabled())
        self.assertFalse(w.dirty())
        self.assertFalse(w.document_bar.isVisible())

    def test_computer_chord_and_octave_release_snapshot(self):
        w = self.window
        QTest.keyPress(w, Qt.Key_A)
        QTest.keyPress(w, Qt.Key_D)
        self.assertEqual(w.pressed_notes, {60, 64})
        w.octave_combo.setCurrentIndex(0)
        QTest.keyPress(w, Qt.Key_G)
        self.assertEqual(w.pressed_notes, {60, 64, 55})
        QTest.keyRelease(w, Qt.Key_A)
        QTest.keyRelease(w, Qt.Key_D)
        QTest.keyRelease(w, Qt.Key_G)
        self.assertFalse(w.pressed_notes)
        self.assertFalse(w.session.transport.notes)

    def test_mouse_and_keyboard_same_note_have_independent_holds(self):
        w = self.window
        key = w.piano_buttons[0]
        QTest.keyPress(w, Qt.Key_A)
        QTest.mousePress(key, Qt.LeftButton, pos=key.rect().center())
        QTest.keyRelease(w, Qt.Key_A)
        self.assertIn(60, w.pressed_notes)
        QTest.mouseRelease(key, Qt.LeftButton, pos=key.rect().center())
        self.assertFalse(w.pressed_notes)

    def test_development_text_editing_does_not_trigger_music(self):
        w = self.window
        w.navigate(0)
        QTest.keyClick(w.name_edit, Qt.Key_A)
        self.assertFalse(w.pressed_notes)

    def test_keyboard_autorepeat_does_not_release_held_note(self):
        w = self.window
        QTest.keyPress(w, Qt.Key_A)
        for kind in [QEvent.KeyRelease, QEvent.KeyPress]:
            QApplication.sendEvent(w, QKeyEvent(kind, Qt.Key_A, Qt.NoModifier, "a", True, 1))
        self.assertEqual(w.pressed_notes, {60})
        QTest.keyRelease(w, Qt.Key_A)
        self.assertFalse(w.pressed_notes)

    def test_rehandshake_never_replays_held_computer_keys(self):
        w = self.window
        QTest.keyPress(w, Qt.Key_A)
        w.rehandshake()
        wait_for(lambda: w.session.ready)
        self.assertFalse(w.input_notes)
        self.assertFalse(w.pressed_notes)
        self.assertFalse(w.session.transport.notes)
        QTest.keyRelease(w, Qt.Key_A)

    def test_compact_home_keeps_stop_button_inside_scroll_view(self):
        w = self.window
        w.resize(1100, 760)
        QApplication.processEvents()
        viewport = w.pages.currentWidget().viewport()
        rect = w.panic_button.rect()
        from PySide6.QtCore import QPoint
        top_left = w.panic_button.mapTo(viewport, QPoint(0, 0))
        bottom_right = w.panic_button.mapTo(viewport, rect.bottomRight())
        self.assertTrue(viewport.rect().contains(top_left))
        self.assertTrue(viewport.rect().contains(bottom_right))

    def test_not_ready_clears_input_snapshots_and_does_not_replay(self):
        w = self.window
        QTest.keyPress(w, Qt.Key_A)
        w.session.transport.line.emit("ERROR 0 NOT_READY")
        self.assertFalse(w.pressed_notes)
        self.assertFalse(w.input_notes)
        self.assertFalse(w.chord_button.isEnabled())

    def test_truthful_capacity_warning_and_unreported_knobs(self):
        w = self.window
        w.session.disconnect_device()
        device = SilentTransport()
        w.session.connect_device("test", transport=device)
        device.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 TONE=FIXED_PIANO")
        self.assertIn("4", w.capacity_label.text())
        self.assertIn("16", w.capacity_warning.text())
        self.assertTrue(w.capacity_warning.isVisible())
        self.assertIn("未上报", w.controls_info.text())

    def test_close_stops_before_save_confirmation_even_when_cancelled(self):
        w = self.window
        w.chord()
        self.assertTrue(w.session.transport.notes)
        seen = []
        def cancel():
            seen.append(set(w.session.transport.notes))
            return False
        with patch.object(w, "confirm_discard", side_effect=cancel):
            w.close()
        self.assertEqual(seen, [set()])
        self.assertTrue(w.isVisible())


if __name__ == "__main__":
    unittest.main()
