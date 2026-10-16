"""Automated audition scheduling and cancellation; fake transport, no COM I/O."""
import os
import unittest
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication
from studio import StudioWindow,configure_fonts
from test_studio import SilentTransport

HELLO='SYNTH/1 CAPS=NOTES,STATUS,PRESET,CONTROL MAX_VOICES=16 SAMPLE_RATE=48000 FW=music-classic16 TONE=PIANO_ROCK'
STATUS='STATUS VOICE_COUNT=0 MAX_VOICE_COUNT=0 STEAL_COUNT=0 SAMPLE_RATE=48000 PRESET=1 VOLUME=8 BEND=512'

class AuditionTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.app=QApplication.instance() or QApplication([]);configure_fonts()
 def setUp(self):
  self.w=StudioWindow();self.w.test_mode=True;self.d=SilentTransport()
  self.w.session.connect_device('test',transport=self.d);self.d.line.emit(HELLO);self.d.line.emit(STATUS)
  self.w.navigate(1);self.d.commands.clear()
 def tearDown(self):
  self.w.close();QApplication.processEvents()
 def advance(self):
  self.w.audition_timer.stop();self.w.audition_step()
 def complete(self):
  count=0
  while self.w.audition_active:
   self.advance();count+=1;self.assertLess(count,100)
  self.assertFalse(self.w.pressed_notes);self.assertFalse(self.w.audition_timer.isActive())
  self.assertTrue(self.w.anchor_button.isEnabled())
 def notes(self,kind):
  return [int(c.split()[1]) for c in self.d.commands if c.startswith(kind+' ')]
 def test_anchors_pair_notes_and_preserve_controls(self):
  self.w.start_audition('anchors');self.assertEqual(self.w.audition_timer.interval(),200)
  self.advance();self.assertEqual(self.w.pressed_notes,{48});self.assertEqual(self.w.audition_timer.interval(),1200)
  self.complete()
  self.assertEqual(self.notes('NOTE_ON'),[48,60,72,84]);self.assertEqual(self.notes('NOTE_OFF'),[48,60,72,84])
  self.assertFalse(any(c.startswith('CONTROL') for c in self.d.commands))
  self.assertIn('不代表验收通过',self.w.audition_hint.text())
 def test_scale_covers_every_semitone(self):
  self.w.start_audition('scale');self.complete()
  self.assertEqual(self.notes('NOTE_ON'),list(range(48,85)));self.assertEqual(self.notes('NOTE_OFF'),list(range(48,85)))
 def test_sixteen_notes_and_capacity_gate(self):
  self.w.start_audition('polyphony');self.advance()
  self.assertEqual(self.w.pressed_notes,set(range(48,80,2)));self.assertEqual(self.w.audition_timer.interval(),2000)
  self.complete();self.assertEqual(self.notes('NOTE_ON'),list(range(48,80,2)))
  self.w.session.device['MAX_VOICES']='4';self.w.connection_changed();self.assertFalse(self.w.polyphony_button.isEnabled())
  before=list(self.d.commands);self.w.start_audition('polyphony');self.assertEqual(self.d.commands,before)
 def test_manual_retrigger_cancels_stale_off(self):
  self.w.start_audition('anchors');self.advance();self.w.note_pressed(48)
  self.assertFalse(self.w.audition_active);self.assertEqual(self.w.pressed_notes,{48})
  before=list(self.d.commands);self.advance();self.assertEqual(self.d.commands,before)
  self.assertEqual(self.d.commands[-1],'NOTE_ON 48 100 0');self.w.note_released(48)
  self.assertEqual(self.d.commands[-1],'NOTE_OFF 48 0')
 def test_navigation_and_focus_cancel_even_in_gap(self):
  for action in (lambda:self.w.navigate(0),lambda:self.w.focus_changed(Qt.ApplicationInactive)):
   self.w.navigate(1);self.w.start_audition('anchors');self.assertFalse(self.w.pressed_notes)
   action();self.assertFalse(self.w.audition_active);self.assertFalse(self.w.audition_events)
   before=list(self.d.commands);self.advance();self.assertEqual(self.d.commands,before)
 def test_expiry_and_disconnect_cancel_without_replay(self):
  self.w.start_audition('polyphony');self.advance();self.d.line.emit('ERROR 0 NOT_READY')
  self.assertFalse(self.w.audition_active);self.assertFalse(self.w.pressed_notes)
  self.d.line.emit(HELLO);self.d.line.emit(STATUS);before=list(self.d.commands);self.advance();self.assertEqual(self.d.commands,before)
  self.w.start_audition('anchors');self.w.session.disconnect_device()
  self.assertFalse(self.w.audition_active);self.assertFalse(self.w.audition_timer.isActive())
 def test_preset_change_cancels_sequence_before_select(self):
  self.w.start_audition('anchors');self.advance()
  self.w.choose_device_preset(self.w.device_preset_combo.findData(0))
  self.assertFalse(self.w.audition_active);self.assertFalse(self.w.pressed_notes)
  self.assertEqual(self.d.commands[-1],'PRESET 0');self.assertIn('NOTE_OFF 48 0',self.d.commands)
 def test_transport_failure_cleans_partial_chord(self):
  self.w.start_audition('polyphony');original=self.d.send
  def fail(text):
   if text.startswith('NOTE_ON 52'):raise OSError('device removed')
   original(text)
  self.d.send=fail;self.advance()
  self.assertFalse(self.w.audition_active);self.assertFalse(self.w.pressed_notes)
  self.assertEqual(self.notes('NOTE_OFF'),[48,50]);self.assertEqual(self.d.commands[-1],'PANIC')
 def test_power_chord_owns_and_releases_three_notes(self):
  self.w.start_audition('anchors');self.advance();self.w.power_chord()
  self.assertFalse(self.w.audition_active);self.assertEqual(self.w.pressed_notes,{60,67,72})
  before=list(self.d.commands);self.advance();self.assertEqual(self.d.commands,before)
  self.w.stop_notes();self.assertFalse(self.w.pressed_notes)
  for note in (60,67,72):self.assertIn(f'NOTE_OFF {note} 0',self.d.commands)
 def test_power_chord_capacity_and_connection_gate(self):
  self.assertTrue(self.w.power_button.isEnabled());self.w.session.device['MAX_VOICES']='2'
  self.w.connection_changed();self.assertFalse(self.w.power_button.isEnabled())
  self.w.session.disconnect_device();self.assertFalse(self.w.power_button.isEnabled())
 def test_render_actual_volume_and_audition_controls(self):
  self.assertEqual(self.w.device_volume.value(),8)
  self.w.resize(1360,940);self.w.show();QApplication.processEvents()
  p=Path(__file__).resolve().parents[1]/'build/host/studio_classic16.png';p.parent.mkdir(parents=True,exist_ok=True)
  self.assertTrue(self.w.grab().save(str(p)));self.assertIn('0 / 16',self.w.voice_hint.text())

if __name__=='__main__':unittest.main()
