"""Host compatibility with both delivered FPGA identities; no serial port opened."""
import os,unittest
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtWidgets import QApplication
from studio_transport import StudioSession
from studio_model import Tone
from test_studio import SilentTransport

class PianoUartTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.app=QApplication.instance() or QApplication([])
 def check_device(self,voices,firmware):
  session=StudioSession();device=SilentTransport()
  try:
   session.connect_device('test',transport=device)
   device.line.emit(f'SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES={voices} SAMPLE_RATE=48000 FW={firmware} TONE=FIXED_PIANO')
   self.assertTrue(session.playable);self.assertTrue(session.fixed_tone)
   self.assertEqual(int(session.device['MAX_VOICES']),voices)
   for note in range(48,48+voices):session.note(note,True)
   ons=[s for s in device.commands if s.startswith('NOTE_ON')]
   self.assertEqual(ons,[f'NOTE_ON {note} 100 0' for note in range(48,48+voices)])
   for note in range(48,48+voices):session.note(note,False)
   offs=[s for s in device.commands if s.startswith('NOTE_OFF')]
   self.assertEqual(offs,[f'NOTE_OFF {note} 0' for note in range(48,48+voices)])
   with self.assertRaises(RuntimeError):session.apply(Tone())
   self.assertIsNone(session.applied)
  finally:session.disconnect_device();QApplication.processEvents()
  self.assertEqual(device.commands[-1],'PANIC')
 def test_uart4(self):self.check_device(4,'piano-v3-uart4')
 def test_uart16(self):self.check_device(16,'piano-pipe16')

if __name__=='__main__':unittest.main()
