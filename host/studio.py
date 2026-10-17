"""FPGA tone studio. Run with Python; --screenshot PATH renders a preview."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import sys

from PySide6.QtCore import Qt, QTimer, QEvent
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QApplication, QFileDialog, QMainWindow, QMessageBox, QLineEdit, QComboBox, QAbstractSpinBox, QWidget,
)
from serial.tools import list_ports

from studio_model import Tone, export_hex, harmonic_preset, load_tone, save_tone
from studio_transport import StudioSession


from studio_ui import STYLE, configure_fonts, StudioViewMixin


class StudioWindow(StudioViewMixin, QMainWindow):
    COMPUTER_KEYS = {int(key): i for i, key in enumerate([
        Qt.Key_A, Qt.Key_W, Qt.Key_S, Qt.Key_E, Qt.Key_D, Qt.Key_F, Qt.Key_T,
        Qt.Key_G, Qt.Key_Y, Qt.Key_H, Qt.Key_U, Qt.Key_J, Qt.Key_K])}

    def __init__(self):
        super().__init__()
        self.setWindowTitle("音色设计台 · FPGA 实时乐器")
        self.resize(1280, 860)
        self.setMinimumSize(1040, 720)
        self.setStyleSheet(STYLE)
        self.tone = Tone()
        self.file_path = None
        self.saved_document = json.dumps(self.tone.document(), sort_keys=True)
        self.session = StudioSession(self)
        self.pressed_notes = self.session.active_notes
        self.input_notes = {}
        self.base_note = 60
        self.piano_buttons = []
        self.rendering = False
        self.test_mode = False
        self._build()
        self.octave_changed(1)
        self.session.changed.connect(self.connection_changed)
        self.session.log.connect(self.log_message)
        self.session.status_changed.connect(self.status_changed)
        self.refresh_ports()
        self.render_tone()
        self.connection_changed()
        self.navigate(1)
        QShortcut(QKeySequence.Save, self).activated.connect(self.save)
        QShortcut(QKeySequence.Open, self).activated.connect(self.load)
        QShortcut(QKeySequence.New, self).activated.connect(self.new)
        QApplication.instance().applicationStateChanged.connect(self.focus_changed)
        QApplication.instance().installEventFilter(self)
        self.log_message("提示", "声场已启动：固定钢琴固件连接后即可演奏；模拟设备不产生声音。")

    def navigate(self, index):
        if self.pages.currentIndex() == 1:
            self.stop_notes()
        self.pages.setCurrentIndex(index)
        self.nav_group.button(index).setChecked(True)
        self.document_bar.setVisible(index == 0)
        self.export_button.setVisible(index == 0)
        self.apply_button.setVisible(index == 0)
        if index == 1:
            self.keyboard.setFocus()
        self.update_document_status()

    @staticmethod
    def note_name(note):
        return ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][note % 12] + str(note // 12 - 1)

    def octave_changed(self, index):
        # This changes future PC events only. Each held input keeps its original
        # MIDI note until release; no unsupported board octave command is sent.
        self.base_note = [48, 60, 72][index]
        for offset, key in enumerate(self.piano_buttons):
            key.note = self.base_note + offset
            key.setText(self.note_name(key.note))
            key.setAccessibleName(f"{self.note_name(key.note)}，电脑键 {key.shortcut}")
        self.render_performance()

    def press_input(self, token, offset):
        if token in self.input_notes or not self.session.playable:
            return
        note = self.base_note + offset
        if note in self.session.pending_releases:
            return
        if note in self.pressed_notes or self.note_pressed(note):
            self.input_notes[token] = note
        self.render_performance()

    def release_input(self, token):
        note = self.input_notes.pop(token, None)
        if note is not None and note not in self.input_notes.values():
            self.note_released(note)
        self.render_performance()

    def eventFilter(self, obj, event):
        if (event.type() not in {QEvent.KeyPress, QEvent.KeyRelease} or
                not isinstance(obj, QWidget) or obj.window() is not self):
            return super().eventFilter(obj, event)
        code = event.key()
        token = ("computer", code)
        if event.type() == QEvent.KeyRelease and token in self.input_notes:
            if not event.isAutoRepeat():
                self.release_input(token)
            return True
        if (self.pages.currentIndex() != 1 or
                isinstance(QApplication.focusWidget(), (QLineEdit, QComboBox, QAbstractSpinBox)) or
                event.modifiers() & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)):
            return super().eventFilter(obj, event)
        if code == Qt.Key_Escape:
            if event.type() == QEvent.KeyPress:
                self.stop_notes()
            return True
        if code in self.COMPUTER_KEYS:
            if event.type() == QEvent.KeyPress and not event.isAutoRepeat():
                self.press_input(token, self.COMPUTER_KEYS[code])
            return True
        return super().eventFilter(obj, event)

    def render_tone(self):
        self.rendering = True
        self.name_edit.setText(self.tone.name)
        self.harmonics.set_values(self.tone.harmonics)
        self.harmonic_count.setText(f"{sum(value > 0 for value in self.tone.harmonics):02d} / 16 启用")
        for key, spin in self.parameter_spins.items():
            spin.setValue(getattr(self.tone, key))
        self.mode_group.button(self.tone.mode).setChecked(True)
        self.mode_description.setText([
            "按住延续，松开释放。", "起音后自动衰减到零；持续电平不参与击发模式。",
            "短按保留起音与衰减，长按进入持续，随后释放。",
        ][self.tone.mode])
        self.rendering = False
        self.select_harmonic(self.harmonics.index)
        self.wave.set_tone(self.tone)
        self.envelope.set_tone(self.tone)
        self.update_document_status()

    def select_harmonic(self, index):
        self.harmonics.index = index
        self.harmonic_label.setText(f"第 {index + 1} 分量 · " + ("基音" if index == 0 else f"{index + 1} 倍频"))
        self.harmonic_spin.blockSignals(True)
        self.harmonic_spin.setValue(self.tone.harmonics[index])
        self.harmonic_spin.blockSignals(False)
        self.harmonics.update()

    def edit_harmonic(self, index, value):
        self.tone.harmonics[index] = value
        self.preset_combo.setCurrentIndex(3)
        self.render_tone()

    def exact_harmonic(self, value):
        self.edit_harmonic(self.harmonics.index, value)

    def set_harmonics(self, kind):
        self.tone.harmonics = harmonic_preset(kind)
        self.preset_combo.setCurrentIndex(0 if kind == "sine" else 3)
        self.render_tone()

    def choose_preset(self, index):
        if index < 3:
            self.tone.harmonics = harmonic_preset(["sine", "soft", "bright"][index])
            self.render_tone()

    def parameter_changed(self, key, value):
        if not self.rendering:
            setattr(self.tone, key, value)
            self.render_tone()

    def name_changed(self, text):
        self.tone.name = text
        self.update_document_status()

    def dirty(self):
        return self.saved_document != json.dumps(self.tone.document(), sort_keys=True) if self.tone.name.strip() else True

    def update_document_status(self):
        try:
            self.tone.validate()
            valid = True
        except ValueError:
            valid = False
        saved = "已保存" if self.file_path and valid and not self.dirty() else "尚未保存"
        prefix = "模拟设备" if self.session.simulated and self.session.ready else "设备"
        if self.session.fixed_tone:
            device = f"设备固定{self.session.fixed_tone_name} · 界面参数未应用"
        elif self.session.pending:
            device = f"{prefix}确认中…"
        elif self.session.applied and self.session.applied.fingerprint() == self.tone.fingerprint():
            device = f"{prefix}已确认"
        elif self.session.applied:
            device = f"{prefix}与草稿不一致"
        else:
            device = f"{prefix}尚未应用"
        self.document_label.setText(f"{'配置文件' if self.file_path else '新建草稿'} · {saved} · {device}")
        self.file_label.setText((str(self.file_path) if self.file_path else "开发草稿 · Ctrl+S 保存 / Ctrl+O 载入")
                               if self.pages.currentIndex() == 0 else "电脑音符与实体琴键共享声部 · Esc 仅停止电脑来源")
        self.apply_button.setEnabled(valid and self.session.ready and "CONFIG" in self.session.capabilities
                                     and self.session.pending is None)
        self.setWindowTitle(f"{self.tone.name or '未命名'}{' *' if not valid or self.dirty() else ''} · 开发草稿"
                            if self.pages.currentIndex() == 0 else "声场 · FPGA 电子钢琴")

    def confirm_discard(self):
        if self.test_mode or not self.dirty():
            return True
        choice = QMessageBox.question(self, "尚未保存", "要保存当前草稿后继续吗？",
                                      QMessageBox.Save | QMessageBox.Discard | QMessageBox.Cancel,
                                      QMessageBox.Save)
        if choice == QMessageBox.Save:
            return self.save()
        return choice == QMessageBox.Discard

    def new(self):
        self.stop_notes()
        if self.confirm_discard():
            self.tone = Tone()
            self.file_path = None
            self.saved_document = json.dumps(self.tone.document(), sort_keys=True)
            self.preset_combo.setCurrentIndex(0)
            self.render_tone()

    def save(self):
        return self.save_to(self.file_path) if self.file_path else self.save_as()

    def save_as(self):
        self.stop_notes()
        path, _ = QFileDialog.getSaveFileName(self, "保存音色配置", str(self.file_path or "新音色.json"), "音色配置 (*.json)")
        return self.save_to(path) if path else False

    def save_to(self, path):
        try:
            save_tone(path, self.tone)
            self.file_path = Path(path)
            self.saved_document = json.dumps(self.tone.document(), sort_keys=True)
            self.update_document_status()
            self.log_message("文件", f"已保存 {path}")
            return True
        except (OSError, ValueError) as exc:
            self.problem("保存失败", exc)
            return False

    def load(self):
        self.stop_notes()
        if not self.confirm_discard():
            return
        path, _ = QFileDialog.getOpenFileName(self, "载入音色配置", "", "音色配置 (*.json)")
        if path:
            self.load_from(path)

    def load_from(self, path):
        try:
            tone = load_tone(path)
        except (OSError, ValueError, TypeError) as exc:
            self.problem("载入失败", exc)
            return False
        self.tone = tone
        self.file_path = Path(path)
        self.saved_document = json.dumps(self.tone.document(), sort_keys=True)
        self.preset_combo.setCurrentIndex(3)
        self.render_tone()
        return True

    def export_table(self):
        self.stop_notes()
        path, _ = QFileDialog.getSaveFileName(self, "导出 1024 点单周期波表", "tone_1024.hex", "16 位十六进制波表 (*.hex)")
        if path:
            try:
                export_hex(path, self.tone)
                self.log_message("文件", f"已导出 {path}（需在 FPGA 工程中接入）")
            except (OSError, ValueError) as exc:
                self.problem("导出失败", exc)

    def refresh_ports(self):
        current = self.port_combo.currentData()
        self.port_combo.clear()
        self.port_combo.addItem("模拟钢琴 · 16声部 / 不发声", "SIM_PIANO")
        self.port_combo.addItem("开发模拟器 · 配置试验", "SIM")
        for port in list_ports.comports():
            self.port_combo.addItem(f"{port.device} · {port.description}", port.device)
        index = self.port_combo.findData(current)
        if index >= 0:
            self.port_combo.setCurrentIndex(index)

    def toggle_connection(self):
        try:
            if self.session.transport is not None:
                self.stop_notes()
                self.session.disconnect_device()
            else:
                self.session.connect_device(self.port_combo.currentData(), int(self.baud_combo.currentText()))
        except (RuntimeError, OSError) as exc:
            self.problem("连接失败", exc)

    def rehandshake(self):
        try:
            self.stop_notes()
            self.session.rehandshake()
        except RuntimeError as exc:
            self.problem("无法重新握手", exc)

    def connection_changed(self):
        connected = self.session.transport is not None
        self.connect_button.setText("断开" if connected else "连接")
        self.port_combo.setEnabled(not connected)
        self.baud_combo.setEnabled(not connected)
        self.refresh_button.setEnabled(not connected)
        self.rehandshake_button.setEnabled(connected)
        self.connection_label.setText(self.session.label)
        if self.connection_label.property("ready") != self.session.ready:
            self.connection_label.setProperty("ready", self.session.ready)
            self.connection_label.style().unpolish(self.connection_label)
            self.connection_label.style().polish(self.connection_label)
        self.traffic_label.setText(f"已发 {self.session.tx_bytes} B · 已收 {self.session.rx_bytes} B")
        playable = self.session.playable
        for key in self.piano_buttons:
            key.setEnabled(playable)
        maximum = int(self.session.device.get("MAX_VOICES", "0"))
        self.chord_button.setEnabled(playable and maximum >= 4)
        self.panic_button.setEnabled(self.session.ready and "NOTES" in self.session.capabilities)
        self.query_button.setEnabled(self.session.ready and "STATUS" in self.session.capabilities)
        self.play_hint.setText("模拟设备只显示音符事件，不产生声音。" if playable and self.session.simulated else
                               f"按住琴键演奏；设备为固定{self.session.fixed_tone_name}，界面参数不改变声音。" if self.session.fixed_tone else
                               "按住琴键演奏。" if playable else "先连接支持演奏的设备；可配置设备需先应用音色。")
        if self.session.ready:
            source = "模拟设备" if self.session.simulated else "真实设备报告"
            self.device_info.setText(f"{source} · 固件 {self.session.device.get('FW', '未提供')}\n"
                                     f"报告支持 {maximum} 声部 · 功能：{', '.join(sorted(self.session.capabilities))}")
        else:
            self.device_info.setText(self.session.label)
            self.pressed_notes.clear()
            self.input_notes.clear()
        self.render_performance()
        self.update_document_status()

    def render_performance(self):
        maximum = int(self.session.device.get("MAX_VOICES", "0")) if self.session.ready else None
        count = self.session.status.get("VOICE_COUNT")
        self.capacity_label.setText(f"{maximum} 声部 / 固件报告" if maximum else "设备尚未报告")
        self.occupancy_label.setText(f"{count if count is not None else '—'} / {maximum or '—'}")
        self.voice_rack.set_status(count, maximum)
        warning = ""
        if self.session.ready and not self.session.simulated and maximum != 16:
            warning = f"固件握手报告 {maximum} 声部；当前项目为16声部，报告信息尚未同步。此处保留设备原值。"
        if count is not None and maximum and count > maximum:
            warning = "设备状态占用超过握手容量；请核对固件的声部报告。" + warning
        self.capacity_warning.setText(warning)
        self.capacity_warning.setVisible(bool(warning))
        self.device_warning.setText(warning)
        self.device_warning.setVisible(bool(warning))
        if self.session.simulated and self.session.ready:
            tone = "模拟钢琴 · 不产生声音" if self.session.fixed_tone else "开发模拟器 · 配置试验"
        elif self.session.fixed_tone:
            tone = f"{self.session.fixed_tone_name} · 固件预设"
        else:
            tone = "固件预设 · 等待设备确认"
        self.tone_label.setText(tone)
        self.freshness_label.setText("模拟状态 · 不代表实物" if self.session.simulated and self.session.ready else
                                     "每秒查询 · 设备报告值" if self.session.status else "等待设备状态数据")
        notes = "  ".join(self.note_name(n) for n in sorted(self.pressed_notes)) or "—"
        self.notes_label.setText("电脑按住的音符  " + notes)
        for key in self.piano_buttons:
            key.held = key.note in self.pressed_notes
            key.update()

    def status_changed(self, values):
        for key, item in self.status_labels.items():
            item.setText(str(values[key]) + (" Hz" if key == "SAMPLE_RATE" else "") if key in values else "—")
        self.render_performance()

    def apply(self):
        try:
            self.stop_notes()
            self.session.apply(self.tone)
        except (RuntimeError, ValueError) as exc:
            self.problem("无法应用", exc)

    def note_pressed(self, note):
        try:
            self.session.note(note, True)
            self.pressed_notes.add(note)
            return True
        except RuntimeError as exc:
            self.log_message("提示", str(exc))
            return False

    def note_released(self, note):
        if note in self.pressed_notes:
            try:
                self.session.note(note, False)
            except RuntimeError as exc:
                self.log_message("提示", str(exc))

    def chord(self):
        self.stop_notes()
        for offset in [0, 4, 7, 12]:
            self.press_input(("chord", offset), offset)

    def stop_notes(self):
        self.input_notes.clear()
        try:
            self.session.panic()
        except RuntimeError as exc:
            self.log_message("提示", str(exc))
        self.render_performance()

    def focus_changed(self, state):
        if state != Qt.ApplicationActive and self.pressed_notes:
            self.stop_notes()

    def log_message(self, kind, text):
        self.log_view.appendPlainText(f"{datetime.now():%H:%M:%S}  [{kind}] {text}")

    def problem(self, title, exc):
        self.log_message("错误", str(exc))
        if not self.test_mode:
            QMessageBox.warning(self, title, str(exc))

    def show_help(self):
        self.stop_notes()
        QMessageBox.information(self, "使用说明", "1. 选择UART串口，115200，连接并等待固件确认。\n"
            "2. 固定钢琴固件无需应用草稿，可直接弹奏。\n"
            "3. 电脑键 A W S E D F T G Y H U J K 对应13个半音；Esc停止电脑音符。\n"
            "4. 音域选择只改变以后新按下的电脑音符，不改变实体键。\n"
            "5. 模拟钢琴有16声部但不发声；开发页草稿不改变固定固件。\n"
            "6. 串口当前不报告旋钮、HDMI或USB触摸状态。\n\n"
            "详细说明：host/README.md")

    def closeEvent(self, event):
        self.stop_notes()
        if not self.confirm_discard():
            event.ignore()
            return
        try:
            self.session.disconnect_device()
        except RuntimeError as exc:
            self.problem("正在断开", exc)
            event.ignore()
            return
        event.accept()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot", type=Path)
    parser.add_argument("--simulate", action="store_true")
    args = parser.parse_args()
    app = QApplication(sys.argv[:1])
    app.setApplicationName("FPGA Tone Studio")
    app.setStyle("Fusion")
    configure_fonts()
    window = StudioWindow()
    window.test_mode = bool(args.screenshot)
    window.show()
    if args.simulate:
        window.toggle_connection()
    if args.screenshot:
        def capture():
            args.screenshot.parent.mkdir(parents=True, exist_ok=True)
            if not window.grab().save(str(args.screenshot)):
                print("Screenshot failed", file=sys.stderr)
                app.exit(1)
                return
            window.close()
            app.quit()
        QTimer.singleShot(500, capture)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
