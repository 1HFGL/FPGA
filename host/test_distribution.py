"""Laptop distribution and silent test-mode checks; no real COM is opened."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import hashlib
import shutil

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtWidgets import QApplication
from studio import StudioWindow, configure_fonts
from studio_transport import StudioSession, MockTransport
from test_studio import SilentTransport, wait_for


class DemoDistributionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        configure_fonts()

    def setUp(self):
        self.window = StudioWindow()
        self.window.test_mode = True

    def tearDown(self):
        self.window.close()
        QApplication.processEvents()

    def test_demo_never_constructs_serial_and_reports_actual_simulation(self):
        with patch("studio_transport.SerialTransport", side_effect=AssertionError("physical serial opened")):
            self.window.start_demo()
            wait_for(lambda: self.window.session.ready)
            session = self.window.session
            self.assertTrue(session.demo_mode)
            self.assertIsInstance(session.transport, MockTransport)
            self.assertEqual(session.device["MAX_VOICES"], "32")
            self.assertEqual(session.device["TONE"], "PIANO_GUITAR")
            self.assertNotIn("CONFIG", session.capabilities)
            self.assertIn("测试", self.window.connection_label.text())
            self.assertIn("不发声", self.window.play_hint.text())
            self.assertFalse(self.window.apply_button.isEnabled())
            self.assertFalse(self.window.device_volume.isEnabled())

    def test_demo_33_notes_steals_one_and_panic_clears_every_note(self):
        self.window.start_demo()
        wait_for(lambda: self.window.session.ready)
        session = self.window.session
        for note in range(48, 81):
            session.note(note, True)
        wait_for(lambda: session.status.get("STEAL_COUNT") == 1)
        self.assertEqual(session.status["VOICE_COUNT"], 32)
        self.assertEqual(session.status["MAX_VOICE_COUNT"], 32)
        self.window.stop_notes()
        wait_for(lambda: session.status.get("VOICE_COUNT") == 0)
        self.assertFalse(session.active_notes)

    def test_entering_and_leaving_demo_preserves_draft_and_stops_notes(self):
        w = self.window
        w.parameter_changed("volume", 111)
        w.start_demo()
        wait_for(lambda: w.session.ready)
        w.press_input(("test", 0), 0)
        self.assertEqual(w.pressed_notes, {60})
        w.toggle_demo()
        self.assertIsNone(w.session.transport)
        self.assertFalse(w.input_notes)
        self.assertEqual(w.tone.volume, 111)

    def test_current_32_voice_real_handshake_has_no_stale_16_voice_warning(self):
        d = SilentTransport()
        self.window.session.connect_device("test", transport=d)
        d.line.emit("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=32 SAMPLE_RATE=48000 FW=uart-dual-v1 TONE=PIANO_GUITAR")
        self.assertEqual(self.window.capacity_warning.text(), "")
        self.assertIn("32", self.window.capacity_label.text())
        self.assertIn("32", self.window.polyphony_button.text())

    def test_cli_self_check_creates_report_without_a_device(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "诊断.json"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("studio.py")),
                                     "--self-check", str(report)], capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
            data = json.loads(report.read_text(encoding="utf-8"))
            self.assertTrue(data["ok"])
            self.assertFalse(data["physical_serial_opened"])
            self.assertFalse(data["audio_generated"])
            self.assertEqual(data["maximum_voices"], 32)
            self.assertTrue(data["checks"]["configuration_roundtrip"])
            self.assertTrue(data["checks"]["panic_releases_all"])

    def test_startup_fits_a_laptop_logical_screen(self):
        from studio_runtime import fit_to_screen
        from PySide6.QtCore import QRect
        screen = unittest.mock.Mock()
        screen.availableGeometry.return_value = QRect(0, 0, 1024, 680)
        with patch.object(self.window, "screen", return_value=screen):
            fit_to_screen(self.window)
        self.assertLessEqual(self.window.minimumHeight(), 632)
        self.assertLessEqual(self.window.height(), 632)


@unittest.skipUnless(os.name == "nt", "Windows installer")
class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.package = self.root / "package"
        (self.package / "app").mkdir(parents=True)
        self.file = self.package / "app/JingzouStudio.exe"
        self.file.write_bytes(b"installation test fixture")
        distribution = Path(__file__).with_name("distribution")
        for name in ["Install.ps1", "Uninstall.ps1", "Uninstall.cmd"]:
            (self.package / name).write_text((distribution/name).read_text(encoding="utf-8-sig"), encoding="utf-8-sig")
        self.manifest = {"application_id":"org.jingzou.studio", "version":"1.0.0",
                         "files":{"JingzouStudio.exe":hashlib.sha256(self.file.read_bytes()).hexdigest()}}
        self.write_manifest()

    def tearDown(self):
        self.temp.cleanup()

    def write_manifest(self):
        (self.package / "package-files.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def install(self, destination):
        return subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                               str(self.package / "Install.ps1"), "-DestinationPath", str(destination),
                               "-NoShortcuts"], capture_output=True, timeout=30)

    def test_install_uninstall_preserves_extra_user_files(self):
        target = self.root / "installed"
        result = self.install(target)
        self.assertEqual(result.returncode, 0, result.stderr)
        draft = target / "my-draft.json"
        draft.write_text("user data", encoding="utf-8")
        result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                 str(target / "Uninstall.ps1")], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(draft.read_text(encoding="utf-8"), "user data")
        self.assertFalse((target / "JingzouStudio.exe").exists())

    def test_rejects_tampering_and_unknown_destination(self):
        target = self.root / "unknown"
        target.mkdir()
        personal = target / "personal.txt"
        personal.write_text("keep me", encoding="utf-8")
        self.assertNotEqual(self.install(target).returncode, 0)
        self.assertEqual(personal.read_text(encoding="utf-8"), "keep me")
        self.file.write_bytes(b"corrupted")
        new = self.root / "new"
        self.assertNotEqual(self.install(new).returncode, 0)
        self.assertFalse(new.exists())

    def test_rejects_traversal_and_uninstall_wrong_identity(self):
        self.manifest["files"] = {"../escape.txt":"0"*64}
        self.write_manifest()
        self.assertNotEqual(self.install(self.root / "new").returncode, 0)
        fake = self.root / "not-an-install"
        fake.mkdir()
        shutil.copy2(self.package / "Uninstall.ps1", fake / "Uninstall.ps1")
        (fake / "installed.json").write_text('{"application_id":"another-app"}', encoding="utf-8")
        result = subprocess.run(["powershell.exe", "-NoProfile", "-File", str(fake/"Uninstall.ps1")],
                                capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((fake / "installed.json").exists())


if __name__ == "__main__":
    unittest.main()
