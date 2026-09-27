"""Audio input, FFT capture and simple latency measurement helpers."""
import time

import numpy as np
import sounddevice as sd
from scipy import signal
from PySide6.QtCore import QThread, Signal


def query_devices():
    devices = []
    try:
        for index, info in enumerate(sd.query_devices()):
            devices.append((index, info))
    except Exception:
        pass
    return devices


class AudioMonitor(QThread):
    block_ready = Signal(object)
    error = Signal(str)

    def __init__(self, device=None, sample_rate=48000, block_size=4096, parent=None):
        super().__init__(parent)
        self.device = device
        self.sample_rate = int(sample_rate)
        self.block_size = int(block_size)
        self._running = False

    def run(self):
        self._running = True
        try:
            with sd.InputStream(
                device=self.device,
                samplerate=self.sample_rate,
                channels=1,
                blocksize=self.block_size,
                dtype="float32",
            ) as stream:
                while self._running:
                    data, _overflowed = stream.read(self.block_size)
                    self.block_ready.emit(np.asarray(data[:, 0], dtype=np.float32).copy())
        except Exception as exc:
            self.error.emit(str(exc))

    def stop(self):
        self._running = False
        self.wait(2000)


class LatencyWorker(QThread):
    result_ready = Signal(float, float)
    error = Signal(str)

    def __init__(self, sample_rate=48000, device=None, parent=None):
        super().__init__(parent)
        self.sample_rate = int(sample_rate)
        self.device = device

    def run(self):
        try:
            sr = self.sample_rate
            total = int(sr * 1.5)
            pulse_len = max(16, int(sr * 0.002))
            t = np.arange(pulse_len, dtype=np.float32) / float(sr)
            pulse = np.sin(2.0 * np.pi * 4000.0 * t).astype(np.float32)
            fade = np.linspace(0.0, 1.0, pulse_len, dtype=np.float32)
            pulse *= fade

            output = np.zeros(total, dtype=np.float32)
            start = int(sr * 0.25)
            output[start:start + pulse_len] = pulse * 0.6

            recording = sd.playrec(
                output,
                samplerate=sr,
                channels=1,
                device=self.device,
                dtype="float32",
            )
            sd.wait()
            rec = np.asarray(recording[:, 0], dtype=np.float32)
            corr = signal.correlate(rec, output, mode="full")
            delay = int(np.argmax(corr) - (len(output) - 1))
            delay_ms = max(0.0, delay * 1000.0 / sr)
            peak = float(np.max(np.abs(rec))) if len(rec) else 0.0
            self.result_ready.emit(delay_ms, peak)
        except Exception as exc:
            self.error.emit(str(exc))