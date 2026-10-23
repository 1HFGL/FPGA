"""32-note audition on the actual NOTES/STATUS-only board capability contract."""
import os,unittest
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtWidgets import QApplication
from studio import StudioWindow,configure_fonts
from test_studio import SilentTransport
HELLO='SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=32 SAMPLE_RATE=48000 FW=uart-dual-v1 TONE=PIANO_GUITAR'
class Poly32Tests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.app=QApplication.instance() or QApplication([]);configure_fonts()
 def setUp(self):
  self.w=StudioWindow();self.w.test_mode=True;self.d=SilentTransport()
  self.w.session.connect_device('test',transport=self.d);self.d.line.emit(HELLO)
  self.w.navigate(1);self.d.commands.clear()
 def tearDown(self):
  self.w.close();QApplication.processEvents()
 def advance(self):
  self.w.audition_timer.stop();self.w.audition_step()
 def test_full_32_notes_and_release_without_preset_controls(self):
  self.assertTrue(self.w.polyphony_button.isEnabled());self.assertEqual(self.w.polyphony_button.text(),'32音测试')
  self.w.start_audition('polyphony');self.advance()
  self.assertEqual(self.w.pressed_notes,set(range(48,80)))
  self.d.line.emit('STATUS VOICE_COUNT=32 MAX_VOICE_COUNT=32 STEAL_COUNT=0 SAMPLE_RATE=48000 PRESET=1 VOLUME=8 BEND=512')
  self.assertIn('32 / 32',self.w.voice_hint.text())
  for _ in range(4):self.advance()
  self.assertFalse(self.w.audition_active);self.assertFalse(self.w.pressed_notes)
  for n in range(48,80):
   self.assertEqual(self.d.commands.count(f'NOTE_ON {n} 100 0'),1)
   self.assertEqual(self.d.commands.count(f'NOTE_OFF {n} 0'),1)
  self.assertFalse(any(c.startswith(('PRESET','CONTROL','FX','DIAG')) for c in self.d.commands))
 def test_cancel_and_16_voice_compatibility(self):
  self.w.start_audition('polyphony');self.advance();self.w.stop_notes()
  self.assertFalse(self.w.pressed_notes);self.assertFalse(self.w.audition_timer.isActive())
  old=list(self.d.commands);self.advance();self.assertEqual(old,self.d.commands)
  self.w.session.device['MAX_VOICES']='16';self.w.connection_changed()
  self.assertEqual(self.w.polyphony_button.text(),'16音测试')
  self.w.start_audition('polyphony');self.advance()
  self.assertEqual(self.w.pressed_notes,set(range(48,80,2)))
 def test_disconnect_cancels_without_replay(self):
  self.w.start_audition('polyphony');self.advance();self.w.session.disconnect_device()
  self.assertFalse(self.w.audition_active);self.assertFalse(self.w.pressed_notes)
  self.assertFalse(self.w.polyphony_button.isEnabled())
if __name__=='__main__':unittest.main()
