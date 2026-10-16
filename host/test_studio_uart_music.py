"""Preset capability, confirmed selection, note release and GUI integration.

Uses an in-process transport; never opens a COM port or synthesizes audio.
"""
import os
import unittest
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtWidgets import QApplication
from studio import StudioWindow
from studio_transport import StudioSession
from studio_model import Tone
from test_studio import SilentTransport

HELLO='SYNTH/1 CAPS=NOTES,STATUS,PRESET MAX_VOICES=16 SAMPLE_RATE=48000 FW=music-pipe16 TONE=PIANO_ROCK'
def status(preset):
    return f'STATUS VOICE_COUNT=3 MAX_VOICE_COUNT=16 STEAL_COUNT=2 SAMPLE_RATE=48000 PRESET={preset}'

class MusicTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.app=QApplication.instance() or QApplication([])

    def setUp(self):
        self.session=StudioSession();self.device=SilentTransport()
        self.session.connect_device('test',transport=self.device)
        self.device.line.emit(HELLO)

    def tearDown(self):
        self.session.disconnect_device();QApplication.processEvents()

    def test_requires_reported_preset_before_playing(self):
        self.assertTrue(self.session.factory_presets)
        self.assertFalse(self.session.playable)
        self.assertEqual(self.device.commands[-1],'STATUS?')
        for bad in ['2','-1','rock','1.0']:
            self.device.line.emit(status(bad));self.assertFalse(self.session.playable)
        self.device.line.emit(status(0));self.assertTrue(self.session.playable)
        self.assertEqual(self.session.preset_name,'摇滚电吉他')
        self.assertFalse(self.session.fixed_tone)
        with self.assertRaises(RuntimeError):self.session.apply(Tone())
        self.assertIsNone(self.session.applied)

    def test_switch_does_not_panic_or_confirm_before_reply(self):
        self.device.line.emit(status(1));self.session.note(60,True)
        before=len(self.device.commands);self.session.select_preset(0)
        self.assertEqual(self.device.commands[before:],['PRESET 0'])
        self.assertFalse(self.session.playable)
        self.assertEqual(self.session.selected_preset,1)
        with self.assertRaises(RuntimeError):self.session.select_preset(1)
        with self.assertRaises(RuntimeError):self.session.note(64,True)
        self.session.note(60,False)
        self.assertEqual(self.device.commands[-1],'NOTE_OFF 60 0')
        self.device.line.emit(status(1));self.assertFalse(self.session.playable)
        self.device.line.emit(status(0));self.assertTrue(self.session.playable)
        self.assertIsNone(self.session.preset_pending)
        self.assertFalse(self.session.preset_timer.isActive())
        for n in range(48,80,2):self.session.note(n,True)
        self.assertEqual(self.device.commands[-16:],[f'NOTE_ON {n} 100 0' for n in range(48,80,2)])

    def test_timeout_and_recovery(self):
        self.device.line.emit(status(1));self.session.select_preset(0)
        self.session._preset_timeout()
        self.assertFalse(self.session.playable);self.assertIsNone(self.session.selected_preset)
        self.session.note(60,False)
        self.device.line.emit(status(0));self.assertTrue(self.session.playable)

    def test_session_expiry_and_reconnect_clear_selection(self):
        self.device.line.emit(status(0));self.session.select_preset(1)
        self.device.line.emit('ERROR 0 NOT_READY')
        self.assertFalse(self.session.ready);self.assertFalse(self.session.playable)
        self.assertIsNone(self.session.selected_preset);self.assertIsNone(self.session.preset_pending)
        self.session.disconnect_device()
        self.device=SilentTransport();self.session.connect_device('test',transport=self.device)
        self.device.line.emit(HELLO);self.assertFalse(self.session.playable)
        self.device.line.emit(status(0));self.assertTrue(self.session.playable)

    def test_rejection_and_invalid_arguments(self):
        self.device.line.emit(status(1))
        for bad in [True,2,-1,'0']:
            with self.assertRaises(ValueError):self.session.select_preset(bad)
        self.session.select_preset(0);self.device.line.emit('ERROR 0 RANGE')
        self.assertIsNone(self.session.preset_pending);self.assertFalse(self.session.playable)
        self.device.line.emit(status(1));self.assertTrue(self.session.playable)

    def test_unknown_identity_cannot_bypass_config(self):
        self.session.device['TONE']='UNKNOWN'
        self.device.line.emit(status(0))
        self.assertFalse(self.session.factory_presets);self.assertFalse(self.session.playable)
        with self.assertRaises(RuntimeError):self.session.select_preset(0)

    def test_ui_switch_is_separate_from_draft(self):
        window=StudioWindow();window.test_mode=True;device=SilentTransport()
        try:
            window.session.connect_device('test',transport=device);device.line.emit(HELLO)
            self.assertFalse(window.piano_buttons[0].isEnabled())
            device.line.emit(status(1))
            self.assertEqual(window.device_preset_combo.currentData(),1)
            self.assertFalse(window.apply_button.isEnabled())
            window.note_pressed(60);before=len(device.commands)
            window.choose_device_preset(window.device_preset_combo.findData(0))
            self.assertEqual(device.commands[before:],['PRESET 0'])
            window.note_released(60)
            self.assertEqual(device.commands[-1],'NOTE_OFF 60 0')
            device.line.emit(status(0));self.assertEqual(window.device_preset_combo.currentData(),0)
            self.assertIn('摇滚电吉他',window.play_hint.text())
            window.pages.setCurrentIndex(1)
            window.show();QApplication.processEvents()
            out=Path(__file__).resolve().parents[1]/'build/host/studio_rock.png'
            out.parent.mkdir(parents=True,exist_ok=True)
            self.assertTrue(window.grab().save(str(out)))
        finally:window.close();QApplication.processEvents()

if __name__=='__main__':unittest.main()
