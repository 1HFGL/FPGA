"""Confirmed atomic performance controls, backpressure, UI coalescing; no COM I/O."""
import os,unittest
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtWidgets import QApplication
from studio_transport import StudioSession
from studio import StudioWindow
from test_studio import SilentTransport
HELLO='SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=16 SAMPLE_RATE=48000 FW=music-ctrl16 TONE=PIANO_ROCK'
def status(v=127,b=512):return f'STATUS VOICE_COUNT=2 MAX_VOICE_COUNT=16 STEAL_COUNT=0 SAMPLE_RATE=48000 PRESET=1 VOLUME={v} BEND={b}'
class ControlTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.app=QApplication.instance() or QApplication([])
 def setUp(self):
  self.s=StudioSession();self.d=SilentTransport();self.s.connect_device('test',transport=self.d);self.d.line.emit(HELLO)
 def tearDown(self):self.s.disconnect_device();QApplication.processEvents()
 def test_requires_complete_status(self):
  with self.assertRaises(RuntimeError):self.s.set_controls(10,0)
  self.d.line.emit('STATUS PRESET=1 VOLUME=127');self.d.line.emit('STATUS BEND=512');self.assertIsNone(self.s.controls)
  for v,b in [('128','512'),('127','1025'),('1.0','512'),('12','-1'),('12','５１２')]:
   self.d.line.emit(status(v,b));self.assertIsNone(self.s.controls)
  self.d.line.emit(status());self.assertEqual(self.s.controls,(127,512))
 def test_atomic_ack_does_not_interrupt_notes(self):
  self.d.line.emit(status());self.s.note(60,True);before=len(self.d.commands)
  self.s.set_controls(64,1024);self.assertEqual(self.d.commands[before:],['CONTROL 64 1024'])
  self.assertEqual(self.s.controls,(127,512));self.assertTrue(self.s.playable)
  self.s.note(60,False);self.assertEqual(self.d.commands[-1],'NOTE_OFF 60 0')
  self.d.line.emit(status(64,0));self.assertEqual(self.s.controls_pending,(64,1024))
  self.d.line.emit(status(64,1024));self.assertIsNone(self.s.controls_pending);self.assertFalse(self.s.control_timer.isActive())
 def test_rejects_range_and_duplicate(self):
  self.d.line.emit(status())
  for v,b in [(True,512),(128,512),(0,-1),(0,1025),(0,False),('1',512)]:
   with self.assertRaises(ValueError):self.s.set_controls(v,b)
  self.s.set_controls(0,0)
  with self.assertRaises(RuntimeError):self.s.set_controls(127,512)
 def test_timeout_and_error_recover_without_replay(self):
  self.d.line.emit(status());self.s.set_controls(0,0);self.s._control_timeout()
  self.assertIsNone(self.s.controls);self.assertIsNone(self.s.controls_pending);self.assertEqual(self.d.commands[-1],'STATUS?')
  self.d.line.emit(status());self.s.set_controls(64,1024);self.d.line.emit('ERROR 0 BUSY')
  self.assertIsNone(self.s.controls);self.assertIsNone(self.s.controls_pending)
  self.d.line.emit(status(64,512));self.assertEqual(self.s.controls,(64,512))
 def test_expiry_and_reconnect_clear_controls(self):
  self.d.line.emit(status());self.s.set_controls(0,0);self.d.line.emit('ERROR 0 NOT_READY')
  self.assertFalse(self.s.performance_controls);self.assertIsNone(self.s.controls);self.assertFalse(self.s.control_timer.isActive())
 def test_old_firmware_cannot_send_controls(self):
  self.d.line.emit(status());self.s.capabilities.remove('CONTROL')
  with self.assertRaises(RuntimeError):self.s.set_controls(0,0)
 def test_send_failure_clears_pending(self):
  self.d.line.emit(status())
  def fail(text):raise RuntimeError('transport full')
  self.d.send=fail
  with self.assertRaises(RuntimeError):self.s.set_controls(0,0)
  self.assertIsNone(self.s.controls_pending);self.assertFalse(self.s.control_timer.isActive())
 def test_ui_coalesces_and_keeps_latest_without_fake_ack(self):
  w=StudioWindow();w.test_mode=True;d=SilentTransport()
  try:
   w.session.connect_device('test',transport=d);d.line.emit(HELLO);self.assertFalse(w.device_volume.isEnabled())
   d.line.emit(status());self.assertTrue(w.device_volume.isEnabled());w.note_pressed(60)
   before=len(d.commands);w.device_volume.setValue(32);w.device_bend.setValue(512);w.control_send_timer.stop();w.send_performance_controls()
   self.assertEqual(d.commands[before:],['CONTROL 32 1024']);self.assertIn('等待设备确认',w.control_hint.text())
   w.device_volume.setValue(64);w.device_bend.setValue(-512);w.control_send_timer.stop();w.send_performance_controls()
   self.assertEqual(d.commands[-1],'CONTROL 32 1024')
   d.line.emit(status(32,1024));self.assertEqual(w.device_volume.value(),64)
   w.control_send_timer.stop();w.send_performance_controls();self.assertEqual(d.commands[-1],'CONTROL 64 0')
   w.note_released(60);self.assertEqual(d.commands[-1],'NOTE_OFF 60 0');d.line.emit(status(64,0))
   w.pages.setCurrentIndex(1);w.show();QApplication.processEvents()
   out=Path(__file__).resolve().parents[1]/'build/host/studio_controls.png';out.parent.mkdir(parents=True,exist_ok=True);self.assertTrue(w.grab().save(str(out)))
  finally:w.control_send_timer.stop();w.close();QApplication.processEvents()
if __name__=='__main__':unittest.main()
