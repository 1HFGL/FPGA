"""Manual board check. Requires an explicit COM port; never auto-selects hardware.

Example: python play_uart_chord.py --port COM5 --voices 16
Run with the GUI disconnected. Audio is synthesized on the FPGA, not this script.
"""
import argparse,re,time
import serial

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--port',required=True)
 p.add_argument('--voices',type=int,choices=[4,16],default=4)
 p.add_argument('--seconds',type=float,default=2)
 p.add_argument('--preset',choices=['piano','rock'],default='piano')
 a=p.parse_args()
 if not .2<=a.seconds<=10:p.error('--seconds must be between 0.2 and 10')
 with serial.Serial(a.port,115200,timeout=.2,write_timeout=1) as device:
  def send(line):device.write((line+'\n').encode('ascii'));device.flush()
  def receive(prefix,seconds=2):
   deadline=time.monotonic()+seconds
   while time.monotonic()<deadline:
    line=device.readline().decode('ascii',errors='replace').strip()
    if line:print(line,flush=True)
    if line.startswith(prefix):return line
   raise RuntimeError('No '+prefix+' reply; check the selected bitstream and COM port.')
  send('HELLO');hello=receive('SYNTH/1 ')
  cap=re.search(r'\bMAX_VOICES=(\d+)\b',hello)
  if not cap or int(cap[1])<a.voices:
   raise RuntimeError('Device does not report the requested voice capacity.')
  if 'TONE=PIANO_ROCK' in hello:
   preset=0 if a.preset=='rock' else 1
   send(f'PRESET {preset}');reply=receive('STATUS ')
   if not re.search(rf'\bPRESET={preset}\b',reply):
    raise RuntimeError('Device did not confirm the requested preset.')
  elif 'TONE=FIXED_PIANO' not in hello or a.preset!='piano':
   raise RuntimeError('Device does not report the requested instrument.')
  notes=[60,64,67,72] if a.voices==4 else list(range(48,80,2))
  try:
   for note in notes:send(f'NOTE_ON {note} 100 0')
   deadline=time.monotonic()+a.seconds
   while time.monotonic()<deadline:
    send('STATUS?');receive('STATUS ');time.sleep(.2)
   for note in notes:send(f'NOTE_OFF {note} 0')
   time.sleep(.15);send('STATUS?');receive('STATUS ')
  finally:
   send('PANIC')
   time.sleep(.1)

if __name__=='__main__':main()
