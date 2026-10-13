import sys
import json
from pathlib import Path

import numpy as np
from PySide6.QtCore import Qt, Signal, QTimer
from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QTabWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QLabel, QPushButton, QComboBox, QSpinBox, QDoubleSpinBox,
    QSlider, QLineEdit, QPlainTextEdit, QGroupBox, QFileDialog, QMessageBox,
    QCheckBox, QTableWidget, QTableWidgetItem, QHeaderView
)
import pyqtgraph as pg

import protocol
import wavetable
from serial_worker import SerialWorker, available_ports
from audio_worker import AudioMonitor, LatencyWorker, query_devices

try:
    import mido
except Exception:
    mido = None


class PianoButton(QPushButton):
    note_on = Signal(int)
    note_off = Signal(int)

    def __init__(self, note, text, parent=None):
        super().__init__(text, parent)
        self.note = int(note)
        self.setMinimumWidth(44)
        self.setMinimumHeight(110)
        self.pressed.connect(lambda: self.note_on.emit(self.note))
        self.released.connect(lambda: self.note_off.emit(self.note))


class MainWindow(QMainWindow):
    midi_event = Signal(str, int, int)

    def __init__(self):
        super().__init__()
        self.setWindowTitle("FPGA 实时乐器控制台")
        self.resize(1360, 860)

        self.serial_worker = None
        self.audio_monitor = None
        self.audio_buffer = np.zeros(8192, dtype=np.float32)
        self.latency_worker = None
        self.midi_input = None
        self.status = {}
        self._build_menu()
        self.tabs = QTabWidget()
        self.setCentralWidget(self.tabs)
        self.tabs.addTab(self.build_connection_tab(), "连接与测试")
        self.tabs.addTab(self.build_instrument_tab(), "乐器控制")
        self.tabs.addTab(self.build_audio_tab(), "频谱与延迟")
        self.tabs.addTab(self.build_wavetable_tab(), "波表生成")
        self.midi_event.connect(self.handle_midi_event)
        self.refresh_ports()
        self.refresh_midi_ports()
        self.refresh_audio_devices()
        self.write_log("INFO", "FPGA 实时乐器控制台已启动")

    def _build_menu(self):
        file_menu = self.menuBar().addMenu("文件")
        save_action = QAction("保存参数", self)
        save_action.triggered.connect(self.save_preset)
        file_menu.addAction(save_action)
        load_action = QAction("加载参数", self)
        load_action.triggered.connect(self.load_preset)
        file_menu.addAction(load_action)
        file_menu.addSeparator()
        exit_action = QAction("退出", self)
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

    def build_connection_tab(self):
        page = QWidget()
        layout = QVBoxLayout(page)

        conn_box = QGroupBox("FPGA UART")
        conn_layout = QHBoxLayout(conn_box)
        conn_layout.addWidget(QLabel("端口"))
        self.port_combo = QComboBox()
        conn_layout.addWidget(self.port_combo, 1)
        self.refresh_button = QPushButton("刷新")
        self.refresh_button.clicked.connect(self.refresh_ports)
        conn_layout.addWidget(self.refresh_button)
        conn_layout.addWidget(QLabel("波特率"))
        self.baud_combo = QComboBox()
        self.baud_combo.addItems(["115200", "921600", "1000000", "2000000"])
        conn_layout.addWidget(self.baud_combo)
        self.connect_button = QPushButton("连接")
        self.connect_button.clicked.connect(self.toggle_serial)
        conn_layout.addWidget(self.connect_button)
        layout.addWidget(conn_box)

        status_box = QGroupBox("实时状态")
        status_layout = QGridLayout(status_box)
        self.status_labels = {}
        for col, key in enumerate(["VOICE_COUNT", "MAX_VOICE_COUNT", "STEAL_COUNT", "SAMPLE_RATE"]):
            status_layout.addWidget(QLabel(key), 0, col * 2)
            label = QLabel("--")
            label.setStyleSheet("font-size: 20px; font-weight: bold; color: #1e88e5;")
            status_layout.addWidget(label, 0, col * 2 + 1)
            self.status_labels[key] = label
        layout.addWidget(status_box)

        test_box = QGroupBox("比赛测试模式")
        test_layout = QHBoxLayout(test_box)
        for count in [1, 4, 8, 16, 32]:
            button = QPushButton(f"TEST {count}")
            button.clicked.connect(lambda checked=False, n=count: self.send_test(n))
            test_layout.addWidget(button)
        clear_button = QPushButton("CLEAR")
        clear_button.clicked.connect(self.send_clear)
        test_layout.addWidget(clear_button)
        status_button = QPushButton("STATUS?")
        status_button.clicked.connect(self.send_status)
        test_layout.addWidget(status_button)
        layout.addWidget(test_box)

        cmd_box = QGroupBox("命令")
        cmd_layout = QHBoxLayout(cmd_box)
        self.command_input = QLineEdit()
        self.command_input.setPlaceholderText("例如 STATUS? / TEST 32 / TIMBRE 2")
        self.command_input.returnPressed.connect(self.send_custom_command)
        cmd_layout.addWidget(self.command_input, 1)
        send_button = QPushButton("发送")
        send_button.clicked.connect(self.send_custom_command)
        cmd_layout.addWidget(send_button)
        layout.addWidget(cmd_box)

        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMaximumBlockCount(2000)
        layout.addWidget(self.log_view, 1)
        return page
    def build_instrument_tab(self):
        page = QWidget()
        layout = QHBoxLayout(page)

        controls = QGroupBox("音色与表情")
        form = QGridLayout(controls)
        row = 0
        form.addWidget(QLabel("音色编号"), row, 0)
        self.timbre_spin = QSpinBox()
        self.timbre_spin.setRange(0, 255)
        form.addWidget(self.timbre_spin, row, 1)
        row += 1
        form.addWidget(QLabel("音量"), row, 0)
        self.volume_slider = QSlider(Qt.Horizontal)
        self.volume_slider.setRange(0, 127)
        self.volume_slider.setValue(100)
        form.addWidget(self.volume_slider, row, 1)
        row += 1
        for name, default in [("Attack", 10), ("Decay", 30), ("Sustain", 90), ("Release", 40)]:
            form.addWidget(QLabel(name), row, 0)
            spin = QSpinBox()
            spin.setRange(0, 127)
            spin.setValue(default)
            setattr(self, f"{name.lower()}_spin", spin)
            form.addWidget(spin, row, 1)
            row += 1
        form.addWidget(QLabel("效果器"), row, 0)
        self.effect_combo = QComboBox()
        self.effect_combo.addItems(["CHORUS", "DELAY", "REVERB"])
        form.addWidget(self.effect_combo, row, 1)
        row += 1
        form.addWidget(QLabel("效果量"), row, 0)
        self.effect_slider = QSlider(Qt.Horizontal)
        self.effect_slider.setRange(0, 127)
        self.effect_slider.setValue(64)
        form.addWidget(self.effect_slider, row, 1)
        row += 1
        send_button = QPushButton("发送音色参数")
        send_button.clicked.connect(self.send_instrument_parameters)
        form.addWidget(send_button, row, 0, 1, 2)
        row += 1
        save_button = QPushButton("保存参数")
        save_button.clicked.connect(self.save_preset)
        load_button = QPushButton("加载参数")
        load_button.clicked.connect(self.load_preset)
        form.addWidget(save_button, row, 0)
        form.addWidget(load_button, row, 1)
        layout.addWidget(controls, 1)

        right = QVBoxLayout()
        piano_box = QGroupBox("虚拟键盘")
        piano_layout = QGridLayout(piano_box)
        self.piano_buttons = []
        base_note = 60
        names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        for index, name in enumerate(names):
            button = PianoButton(base_note + index, name)
            button.note_on.connect(self.send_note_on)
            button.note_off.connect(self.send_note_off)
            piano_layout.addWidget(button, 0, index)
            self.piano_buttons.append(button)
        right.addWidget(piano_box)

        octave_box = QGroupBox("键盘设置")
        octave_layout = QHBoxLayout(octave_box)
        octave_layout.addWidget(QLabel("八度偏移"))
        self.octave_spin = QSpinBox()
        self.octave_spin.setRange(-3, 3)
        octave_layout.addWidget(self.octave_spin)
        octave_layout.addWidget(QLabel("力度"))
        self.velocity_spin = QSpinBox()
        self.velocity_spin.setRange(1, 127)
        self.velocity_spin.setValue(100)
        octave_layout.addWidget(self.velocity_spin)
        right.addWidget(octave_box)

        midi_box = QGroupBox("MIDI 输入")
        midi_layout = QHBoxLayout(midi_box)
        self.midi_combo = QComboBox()
        midi_layout.addWidget(self.midi_combo, 1)
        refresh_midi = QPushButton("刷新")
        refresh_midi.clicked.connect(self.refresh_midi_ports)
        midi_layout.addWidget(refresh_midi)
        self.midi_connect_button = QPushButton("连接 MIDI")
        self.midi_connect_button.clicked.connect(self.toggle_midi)
        midi_layout.addWidget(self.midi_connect_button)
        self.midi_status = QLabel("未连接")
        midi_layout.addWidget(self.midi_status)
        right.addWidget(midi_box)
        right.addStretch(1)
        layout.addLayout(right, 2)
        return page
    def build_audio_tab(self):
        page = QWidget()
        layout = QVBoxLayout(page)
        device_box = QGroupBox("音频输入")
        device_layout = QHBoxLayout(device_box)
        device_layout.addWidget(QLabel("输入设备"))
        self.audio_device_combo = QComboBox()
        device_layout.addWidget(self.audio_device_combo, 1)
        refresh_audio = QPushButton("刷新")
        refresh_audio.clicked.connect(self.refresh_audio_devices)
        device_layout.addWidget(refresh_audio)
        self.audio_start_button = QPushButton("开始采集")
        self.audio_start_button.clicked.connect(self.toggle_audio_monitor)
        device_layout.addWidget(self.audio_start_button)
        device_layout.addWidget(QLabel("采样率"))
        self.audio_rate_spin = QSpinBox()
        self.audio_rate_spin.setRange(8000, 192000)
        self.audio_rate_spin.setValue(48000)
        device_layout.addWidget(self.audio_rate_spin)
        layout.addWidget(device_box)

        self.fft_plot = pg.PlotWidget()
        self.fft_plot.setTitle("实时 FFT 频谱")
        self.fft_plot.setLabel("bottom", "Frequency", units="Hz")
        self.fft_plot.setLabel("left", "Magnitude", units="dB")
        self.fft_curve = self.fft_plot.plot(pen=pg.mkPen("#00d1ff", width=2))
        layout.addWidget(self.fft_plot, 1)
        self.peak_label = QLabel("检测到的有效谱峰：--")
        self.peak_label.setStyleSheet("font-size: 18px; font-weight: bold;")
        layout.addWidget(self.peak_label)

        latency_box = QGroupBox("延迟测量")
        latency_layout = QHBoxLayout(latency_box)
        self.latency_button = QPushButton("开始声学延迟测试")
        self.latency_button.clicked.connect(self.run_latency_test)
        latency_layout.addWidget(self.latency_button)
        self.latency_label = QLabel("尚未测量")
        latency_layout.addWidget(self.latency_label, 1)
        layout.addWidget(latency_box)
        return page

    def build_wavetable_tab(self):
        page = QWidget()
        layout = QVBoxLayout(page)
        controls = QGroupBox("波表参数")
        form = QGridLayout(controls)
        form.addWidget(QLabel("波形"), 0, 0)
        self.wave_kind = QComboBox()
        self.wave_kind.addItems(wavetable.WAVEFORMS)
        form.addWidget(self.wave_kind, 0, 1)
        form.addWidget(QLabel("采样点"), 1, 0)
        self.wave_length = QSpinBox()
        self.wave_length.setRange(16, 8192)
        self.wave_length.setValue(256)
        form.addWidget(self.wave_length, 1, 1)
        form.addWidget(QLabel("谐波数"), 2, 0)
        self.wave_harmonics = QSpinBox()
        self.wave_harmonics.setRange(1, 64)
        self.wave_harmonics.setValue(8)
        form.addWidget(self.wave_harmonics, 2, 1)
        form.addWidget(QLabel("幅度"), 3, 0)
        self.wave_amplitude = QDoubleSpinBox()
        self.wave_amplitude.setRange(0.01, 1.0)
        self.wave_amplitude.setSingleStep(0.05)
        self.wave_amplitude.setValue(1.0)
        form.addWidget(self.wave_amplitude, 3, 1)
        generate = QPushButton("生成并预览")
        generate.clicked.connect(self.generate_wave_preview)
        form.addWidget(generate, 4, 0, 1, 2)
        layout.addWidget(controls)

        self.wave_plot = pg.PlotWidget()
        self.wave_plot.setTitle("波表预览")
        self.wave_curve = self.wave_plot.plot(pen=pg.mkPen("#ffb300", width=2))
        layout.addWidget(self.wave_plot, 1)

        export_layout = QHBoxLayout()
        for label, suffix in [("导出 HEX", "hex"), ("导出 MIF", "mif"), ("导出 CSV", "csv")]:
            button = QPushButton(label)
            button.clicked.connect(lambda checked=False, s=suffix: self.export_wave(s))
            export_layout.addWidget(button)
        layout.addLayout(export_layout)
        self.current_wave = None
        return page
    def write_log(self, tag, text):
        if hasattr(self, "log_view"):
            self.log_view.appendPlainText(f"[{tag}] {text}")

    def refresh_ports(self):
        self.port_combo.clear()
        ports = available_ports()
        self.port_combo.addItems(ports)
        if not ports:
            self.write_log("INFO", "未发现串口设备")

    def toggle_serial(self):
        if self.serial_worker is not None:
            self.serial_worker.stop()
            self.serial_worker = None
            self.connect_button.setText("连接")
            self.write_log("INFO", "串口已断开")
            return
        port = self.port_combo.currentText().strip()
        if not port:
            QMessageBox.warning(self, "串口", "没有可用串口，请先连接开发板或选择端口。")
            return
        baud = int(self.baud_combo.currentText())
        self.serial_worker = SerialWorker(port, baud)
        self.serial_worker.line_received.connect(self.handle_serial_line)
        self.serial_worker.error.connect(lambda msg: self.write_log("ERROR", msg))
        self.serial_worker.opened.connect(lambda p: self.write_log("INFO", f"串口已连接: {p}"))
        self.serial_worker.start()
        self.connect_button.setText("断开")

    def send_custom_command(self):
        text = self.command_input.text().strip()
        if text:
            self.send_command(text)
            self.command_input.clear()

    def send_command(self, text):
        self.write_log("TX", text)
        try:
            if self.serial_worker is not None:
                self.serial_worker.send(text)
        except Exception as exc:
            self.write_log("ERROR", str(exc))

    def handle_serial_line(self, line):
        self.write_log("RX", line)
        status = protocol.parse_status(line)
        if status:
            self.status.update(status)
            for key, label in self.status_labels.items():
                if key in status:
                    label.setText(str(status[key]))

    def send_status(self):
        self.send_command(protocol.status_command())

    def send_test(self, count):
        self.send_command(protocol.test_command(count))

    def send_clear(self):
        self.send_command(protocol.clear_command())

    def refresh_midi_ports(self):
        self.midi_combo.clear()
        if mido is None:
            self.midi_status.setText("mido 未安装")
            return
        try:
            names = mido.get_input_names()
            self.midi_combo.addItems(names)
            if not names:
                self.midi_status.setText("未发现 MIDI 输入")
            else:
                self.midi_status.setText("未连接")
        except Exception as exc:
            self.midi_status.setText("MIDI 后端不可用")
            self.write_log("INFO", f"MIDI 后端不可用: {exc}")

    def toggle_midi(self):
        if self.midi_input is not None:
            try:
                self.midi_input.close()
            except Exception:
                pass
            self.midi_input = None
            self.midi_connect_button.setText("连接 MIDI")
            self.midi_status.setText("未连接")
            return
        if mido is None or not self.midi_combo.currentText():
            QMessageBox.warning(self, "MIDI", "没有可用的 MIDI 输入。可先使用虚拟键盘。")
            return
        try:
            self.midi_input = mido.open_input(self.midi_combo.currentText(), callback=self._midi_callback)
            self.midi_connect_button.setText("断开 MIDI")
            self.midi_status.setText("已连接")
        except Exception as exc:
            QMessageBox.warning(self, "MIDI", str(exc))

    def _midi_callback(self, message):
        if message.type == "note_on" and message.velocity > 0:
            self.midi_event.emit("on", int(message.note), int(message.velocity))
        elif message.type == "note_off" or (message.type == "note_on" and message.velocity == 0):
            self.midi_event.emit("off", int(message.note), 0)

    def handle_midi_event(self, kind, note, velocity):
        if kind == "on":
            self.send_note_on(note, velocity)
        else:
            self.send_note_off(note)

    def send_note_on(self, note, velocity=None):
        note = int(note) + int(self.octave_spin.value()) * 12
        velocity = int(self.velocity_spin.value()) if velocity is None else int(velocity)
        self.send_command(protocol.note_on_command(note, velocity, 0))

    def send_note_off(self, note):
        note = int(note) + int(self.octave_spin.value()) * 12
        self.send_command(protocol.note_off_command(note, 0))

    def send_instrument_parameters(self):
        self.send_command(protocol.timbre_command(self.timbre_spin.value()))
        self.send_command(protocol.adsr_command(
            self.attack_spin.value(), self.decay_spin.value(),
            self.sustain_spin.value(), self.release_spin.value()
        ))
        self.send_command(protocol.volume_command(self.volume_slider.value()))
        self.send_command(protocol.effect_command(self.effect_combo.currentText(), self.effect_slider.value()))

    def keyPressEvent(self, event):
        if event.isAutoRepeat():
            return
        mapping = {"z": 0, "s": 1, "x": 2, "d": 3, "c": 4, "v": 5, "g": 6, "b": 7, "h": 8, "n": 9, "j": 10, "m": 11}
        key = event.text().lower()
        if key in mapping:
            self.send_note_on(60 + mapping[key])
        else:
            super().keyPressEvent(event)

    def keyReleaseEvent(self, event):
        if event.isAutoRepeat():
            return
        mapping = {"z": 0, "s": 1, "x": 2, "d": 3, "c": 4, "v": 5, "g": 6, "b": 7, "h": 8, "n": 9, "j": 10, "m": 11}
        key = event.text().lower()
        if key in mapping:
            self.send_note_off(60 + mapping[key])
        else:
            super().keyReleaseEvent(event)

    def closeEvent(self, event):
        if self.serial_worker is not None:
            self.serial_worker.stop()
        if self.audio_monitor is not None:
            self.audio_monitor.stop()
        if self.midi_input is not None:
            try:
                self.midi_input.close()
            except Exception:
                pass
        event.accept()
    def refresh_audio_devices(self):
        self.audio_device_combo.clear()
        for index, info in query_devices():
            name = info.get("name", f"Device {index}")
            max_in = int(info.get("max_input_channels", 0))
            if max_in > 0:
                self.audio_device_combo.addItem(f"{index}: {name}", index)
        if self.audio_device_combo.count() == 0:
            self.write_log("INFO", "未发现音频输入设备")

    def toggle_audio_monitor(self):
        if self.audio_monitor is not None:
            self.audio_monitor.stop()
            self.audio_monitor = None
            self.audio_start_button.setText("开始采集")
            return
        device = self.audio_device_combo.currentData()
        rate = self.audio_rate_spin.value()
        self.audio_monitor = AudioMonitor(device=device, sample_rate=rate, block_size=4096)
        self.audio_monitor.block_ready.connect(self.on_audio_block)
        self.audio_monitor.error.connect(lambda msg: self.write_log("ERROR", f"音频: {msg}"))
        self.audio_monitor.start()
        self.audio_start_button.setText("停止采集")

    def on_audio_block(self, data):
        from scipy.signal import find_peaks
        data = np.asarray(data, dtype=np.float32)
        if len(data) < 64:
            return
        n = min(4096, len(data))
        block = data[-n:]
        window = np.hanning(n).astype(np.float32)
        spectrum = np.fft.rfft(block * window)
        magnitude = 20.0 * np.log10(np.maximum(np.abs(spectrum) / n, 1e-12))
        freqs = np.fft.rfftfreq(n, d=1.0 / float(self.audio_rate_spin.value()))
        self.fft_curve.setData(freqs, magnitude)
        threshold = max(-100.0, float(np.max(magnitude)) - 30.0)
        peaks, properties = find_peaks(magnitude, height=threshold)
        self.peak_label.setText(f"检测到的有效谱峰：{len(peaks)}")

    def run_latency_test(self):
        if self.latency_worker is not None:
            return
        self.latency_label.setText("测量中...")
        self.latency_worker = LatencyWorker(sample_rate=self.audio_rate_spin.value())
        self.latency_worker.result_ready.connect(self.on_latency_result)
        self.latency_worker.error.connect(lambda msg: self.latency_label.setText(f"失败: {msg}"))
        self.latency_worker.finished.connect(self._clear_latency_worker)
        self.latency_worker.start()

    def _clear_latency_worker(self):
        self.latency_worker = None

    def on_latency_result(self, delay_ms, peak):
        self.latency_label.setText(f"估算延迟：{delay_ms:.2f} ms  峰值：{peak:.4f}")

    def generate_wave_preview(self):
        self.current_wave = wavetable.generate_waveform(
            self.wave_kind.currentText(),
            self.wave_length.value(),
            self.wave_harmonics.value(),
            self.wave_amplitude.value(),
        )
        self.wave_curve.setData(np.arange(len(self.current_wave)), self.current_wave)

    def export_wave(self, suffix):
        if self.current_wave is None:
            self.generate_wave_preview()
        path, _ = QFileDialog.getSaveFileName(
            self, "导出波表", f"waveform.{suffix}",
            f"{suffix.upper()} (*.{suffix});;All Files (*)"
        )
        if not path:
            return
        if suffix == "hex":
            wavetable.export_hex(path, self.current_wave)
        elif suffix == "mif":
            wavetable.export_mif(path, self.current_wave)
        else:
            wavetable.export_csv(path, self.current_wave)
        QMessageBox.information(self, "导出完成", path)

    def preset_data(self):
        return {
            "timbre": self.timbre_spin.value(),
            "volume": self.volume_slider.value(),
            "attack": self.attack_spin.value(),
            "decay": self.decay_spin.value(),
            "sustain": self.sustain_spin.value(),
            "release": self.release_spin.value(),
            "effect": self.effect_combo.currentText(),
            "effect_value": self.effect_slider.value(),
        }

    def save_preset(self):
        path, _ = QFileDialog.getSaveFileName(self, "保存参数", "preset.json", "JSON (*.json)")
        if path:
            Path(path).write_text(json.dumps(self.preset_data(), ensure_ascii=False, indent=2), encoding="utf-8")

    def load_preset(self):
        path, _ = QFileDialog.getOpenFileName(self, "加载参数", "", "JSON (*.json)")
        if not path:
            return
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
            self.timbre_spin.setValue(int(data.get("timbre", 0)))
            self.volume_slider.setValue(int(data.get("volume", 100)))
            self.attack_spin.setValue(int(data.get("attack", 10)))
            self.decay_spin.setValue(int(data.get("decay", 30)))
            self.sustain_spin.setValue(int(data.get("sustain", 90)))
            self.release_spin.setValue(int(data.get("release", 40)))
            self.effect_combo.setCurrentText(str(data.get("effect", "CHORUS")))
            self.effect_slider.setValue(int(data.get("effect_value", 64)))
        except Exception as exc:
            QMessageBox.warning(self, "加载参数", str(exc))


def run_selftest():
    window = MainWindow()
    window.generate_wave_preview()
    assert window.current_wave is not None
    status = protocol.parse_status("VOICE_COUNT=32 MAX_VOICE_COUNT=32 STEAL_COUNT=1")
    assert status["VOICE_COUNT"] == 32
    print("SELFTEST PASS")
    window.close()
    return 0


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("FPGA Real-time Instrument Console")
    if "--selftest" in sys.argv:
        return run_selftest()
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())