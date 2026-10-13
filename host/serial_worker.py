"""Background serial reader/writer for the FPGA UART command channel."""
import threading
import time

import serial
from serial.tools import list_ports
from PySide6.QtCore import QThread, Signal


def available_ports():
    return [port.device for port in list_ports.comports()]


class SerialWorker(QThread):
    line_received = Signal(str)
    error = Signal(str)
    opened = Signal(str)
    closed = Signal()

    def __init__(self, port, baudrate=115200, parent=None):
        super().__init__(parent)
        self.port_name = str(port)
        self.baudrate = int(baudrate)
        self._running = False
        self._serial = None
        self._lock = threading.Lock()

    def run(self):
        self._running = True
        try:
            self._serial = serial.Serial(
                self.port_name,
                self.baudrate,
                timeout=0.15,
                write_timeout=0.5,
            )
            self.opened.emit(self.port_name)
            buffer = bytearray()
            while self._running:
                data = self._serial.read(256)
                if data:
                    buffer.extend(data)
                    while b"\n" in buffer:
                        raw, _, rest = buffer.partition(b"\n")
                        buffer = bytearray(rest)
                        text = raw.decode("utf-8", errors="replace").strip()
                        if text:
                            self.line_received.emit(text)
                else:
                    time.sleep(0.005)
        except Exception as exc:
            self.error.emit(str(exc))
        finally:
            self._close_serial()
            self.closed.emit()

    def send(self, text):
        payload = (str(text).rstrip() + "\n").encode("utf-8")
        with self._lock:
            if self._serial is None or not self._serial.is_open:
                raise RuntimeError("Serial port is not open")
            self._serial.write(payload)
            self._serial.flush()

    def stop(self):
        self._running = False
        self.wait(1500)

    def _close_serial(self):
        with self._lock:
            if self._serial is not None:
                try:
                    self._serial.close()
                except Exception:
                    pass
                self._serial = None