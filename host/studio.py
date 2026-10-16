"""FPGA tone studio. Run with Python; --screenshot PATH renders a preview."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import sys

from PySide6.QtCore import Qt, QTimer, QSignalBlocker
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QApplication, QFileDialog, QMainWindow, QMessageBox,
)
from serial.tools import list_ports

from studio_model import Tone, export_hex, harmonic_preset, load_tone, save_tone
from studio_transport import StudioSession


from studio_ui import STYLE, configure_fonts, StudioViewMixin


class StudioWindow(StudioViewMixin, QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("音色设计台 · FPGA 实时乐器")
        self.resize(1360, 940)
        self.setMinimumSize(1100, 760)
        self.setStyleSheet(STYLE)
        self.tone = Tone()
        self.file_path = None
        self.saved_document = None
        self.session = StudioSession(self)
        self.pressed_notes = set()
        self.piano_buttons = []
        self.rendering = False
        self.test_mode = False
        self.control_dirty = False
        self.control_send_timer = QTimer(self)
        self.control_send_timer.setSingleShot(True)
        self.control_send_timer.timeout.connect(self.send_performance_controls)
        self.audition_active = False
        self.audition_events = []
        self.audition_timer = QTimer(self)
        self.audition_timer.setSingleShot(True)
        self.audition_timer.timeout.connect(self.audition_step)
        self._build()
        self.session.changed.connect(self.connection_changed)
        self.session.log.connect(self.log_message)
        self.session.status_changed.connect(self.status_changed)
        self.refresh_ports()
        self.render_tone()
        self.connection_changed()
        QShortcut(QKeySequence.Save, self).activated.connect(self.save)
        QShortcut(QKeySequence.Open, self).activated.connect(self.load)
        QShortcut(QKeySequence.New, self).activated.connect(self.new)
        QApplication.instance().applicationStateChanged.connect(self.focus_changed)
        self.log_message("提示", "音色设计台已启动；连接模拟设备可试用，模拟设备不产生声音。")

    def navigate(self, index):
        if self.pages.currentIndex() == 1:
            self.stop_notes()
        self.pages.setCurrentIndex(index)
        self.nav_group.button(index).setChecked(True)

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
        saved = "已保存" if valid and not self.dirty() else "尚未保存"
        prefix = "模拟设备" if self.session.simulated and self.session.ready else "设备"
        if self.session.factory_presets:
            device = f"设备音色：{self.session.preset_name} · 草稿参数未应用"
        elif self.session.fixed_tone:
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
        self.file_label.setText(str(self.file_path) if self.file_path else "尚未保存到文件 · Ctrl+S 保存，Ctrl+O 载入")
        self.apply_button.setEnabled(valid and self.session.ready and "CONFIG" in self.session.capabilities
                                     and self.session.pending is None)
        self.setWindowTitle(f"{self.tone.name or '未命名'}{' *' if not valid or self.dirty() else ''} · 音色设计台")

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
        if self.confirm_discard():
            self.tone = Tone()
            self.file_path = None
            self.saved_document = None
            self.preset_combo.setCurrentIndex(0)
            self.render_tone()

    def save(self):
        return self.save_to(self.file_path) if self.file_path else self.save_as()

    def save_as(self):
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
        self.port_combo.addItem("模拟设备 · 试用", "SIM")
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

    def connection_changed(self):
        connected = self.session.transport is not None
        self.connect_button.setText("断开" if connected else "连接")
        self.port_combo.setEnabled(not connected)
        self.baud_combo.setEnabled(not connected)
        self.refresh_button.setEnabled(not connected)
        self.connection_label.setText(self.session.label)
        if self.connection_label.property("ready") != self.session.ready:
            self.connection_label.setProperty("ready", self.session.ready)
            self.connection_label.style().unpolish(self.connection_label)
            self.connection_label.style().polish(self.connection_label)
        self.traffic_label.setText(f"已发 {self.session.tx_bytes} B · 已收 {self.session.rx_bytes} B")
        playable = self.session.playable
        if not playable and self.audition_active:
            self.stop_notes()
        for key in self.piano_buttons:
            key.setEnabled(playable)
        maximum = int(self.session.device.get("MAX_VOICES", "0"))
        self.chord_button.setEnabled(playable and maximum >= 4)
        self.power_button.setEnabled(playable and maximum >= 3)
        can_audition = playable and self.session.factory_presets and not self.audition_active
        self.anchor_button.setEnabled(can_audition)
        self.scale_button.setEnabled(can_audition)
        self.polyphony_button.setEnabled(can_audition and maximum >= 16)
        voices = self.session.status.get("VOICE_COUNT", "—")
        self.voice_hint.setText(f"设备报告当前声部：{voices} / {maximum or '—'}（含释放尾音）")
        self.panic_button.setEnabled(self.session.ready and "NOTES" in self.session.capabilities)
        self.query_button.setEnabled(self.session.ready and "STATUS" in self.session.capabilities)
        self.device_preset_combo.setEnabled(self.session.factory_presets and self.session.preset_pending is None)
        preset = self.session.preset_pending if self.session.preset_pending is not None else self.session.selected_preset
        self.device_preset_combo.setCurrentIndex(self.device_preset_combo.findData(preset))
        self.play_hint.setText("模拟设备只显示音符事件，不产生声音。" if playable and self.session.simulated else
                               "正在等待设备确认音色；已按下的音符仍可松开。" if self.session.preset_pending is not None else
                               f"设备音色：{self.session.preset_name}。" if self.session.factory_presets else
                               f"按住琴键演奏；设备为固定{self.session.fixed_tone_name}，界面参数不改变声音。" if self.session.fixed_tone else
                               "按住琴键演奏。" if playable else "先连接支持演奏的设备；可配置设备需先应用音色。")
        if self.session.ready:
            source = "模拟设备" if self.session.simulated else "真实设备报告"
            self.device_info.setText(f"{source} · 固件 {self.session.device.get('FW', '未提供')}\n"
                                     f"报告支持 {maximum} 声部 · 功能：{', '.join(sorted(self.session.capabilities))}")
        else:
            self.device_info.setText(self.session.label)
            self.pressed_notes.clear()
        self.render_performance_controls()
        self.update_document_status()

    def performance_edited(self, value):
        if not self.session.performance_controls or self.session.controls is None:
            return
        self.control_dirty = True
        if not self.control_send_timer.isActive():
            self.control_send_timer.start(40)
        self.render_performance_controls()

    def send_performance_controls(self):
        if not self.control_dirty or self.session.controls_pending is not None:
            return
        self.control_dirty = False
        try:
            self.session.set_controls(self.device_volume.value(), self.device_bend.value() + 512)
        except (RuntimeError, ValueError) as exc:
            self.log_message("提示", str(exc))
            self.render_performance_controls()

    def render_performance_controls(self):
        enabled = self.session.performance_controls and self.session.controls is not None
        for widget in (self.device_volume, self.device_bend, self.center_bend_button):
            widget.setEnabled(enabled)
        if not enabled:
            self.control_dirty = False
            self.control_send_timer.stop()
            self.control_hint.setText("等待设备确认控制状态。" if self.session.performance_controls else "当前设备未提供音量／弯音控制；设计页草稿不会改变固件预设。")
            return
        if not self.control_dirty:
            values = self.session.controls_pending or self.session.controls
            with QSignalBlocker(self.device_volume), QSignalBlocker(self.device_bend):
                self.device_volume.setValue(values[0])
                self.device_bend.setValue(values[1] - 512)
        elif self.session.controls_pending is None and not self.control_send_timer.isActive():
            self.control_send_timer.start(40)
        volume, bend = self.session.controls
        state = " · 修改待发送" if self.control_dirty else " · 等待设备确认" if self.session.controls_pending is not None else ""
        self.control_hint.setText(f"设备目标：音量 {volume}/127 · 弯音 {(bend-512)/256:+.2f} 半音{state}；固件平滑应用到持续音和尾音。")

    def choose_device_preset(self, index):
        if self.audition_active:
            self.stop_notes()
        try:
            # Do not PANIC: existing voices and release tails keep their instrument.
            self.session.select_preset(self.device_preset_combo.itemData(index))
        except (RuntimeError, ValueError) as exc:
            self.problem("无法切换音色", exc)
            self.connection_changed()

    def status_changed(self, values):
        for key, item in self.status_labels.items():
            item.setText(str(values[key]) + (" Hz" if key == "SAMPLE_RATE" else "") if key in values else "—")

    def apply(self):
        try:
            self.stop_notes()
            self.session.apply(self.tone)
        except (RuntimeError, ValueError) as exc:
            self.problem("无法应用", exc)

    def note_pressed(self, note):
        if self.audition_active:
            self.stop_notes()
        try:
            self.session.note(note, True)
            self.pressed_notes.add(note)
        except (RuntimeError, OSError) as exc:
            self.log_message("提示", str(exc))

    def note_released(self, note):
        if note in self.pressed_notes:
            try:
                self.session.note(note, False)
            except (RuntimeError, OSError) as exc:
                self.log_message("提示", str(exc))
            self.pressed_notes.discard(note)

    def chord(self):
        self.stop_notes()
        for note in [60, 64, 67, 72]:
            self.note_pressed(note)

    def power_chord(self):
        self.stop_notes()
        for note in (60, 67, 72):
            self.note_pressed(note)

    def stop_notes(self):
        was_audition = self.audition_active
        self.audition_active = False
        self.audition_timer.stop()
        self.audition_events.clear()
        if was_audition:
            self.audition_hint.setText("试听已停止；板上按键不受影响。")
        for note in list(self.pressed_notes):
            self.note_released(note)
        try:
            self.session.panic()
        except (RuntimeError, OSError) as exc:
            self.log_message("提示", str(exc))
        if was_audition:
            self.connection_changed()

    def start_audition(self, kind):
        if not self.session.playable or not self.session.factory_presets:
            return
        maximum = int(self.session.device.get("MAX_VOICES", "0"))
        if kind == "polyphony" and maximum < 16:
            return
        if kind not in ("anchors", "scale", "polyphony"):
            raise ValueError("Unknown audition")
        self.stop_notes()
        if kind == "polyphony":
            groups = [(tuple(range(48, 80, 2)), "16音压力测试", 2000)]
        elif kind == "anchors":
            groups = [((n,), name, 1200) for n, name in ((48, "C3"), (60, "C4"), (72, "C5"), (84, "C6"))]
        else:
            groups = [((n,), f"音阶 MIDI {n}", 250) for n in range(48, 85)]
        # QTimer schedules one event at a time; no sleeping or catch-up burst.
        # Cancel old events before any manual note/preset/navigation/session change.
        self.audition_events = [((), (), 200, "等待旧尾音结束")]
        for notes, name, hold in groups:
            self.audition_events.extend([(notes, (), hold, name), ((), notes, 200, name + " · 松键")])
        self.audition_active = True
        self.log_message("试听", f"开始{kind}，使用当前设备音色／音量；程序不判断听感是否合格")
        self.audition_step()

    def audition_step(self):
        if not self.audition_active:
            return
        if not self.session.playable:
            self.stop_notes()
            return
        if not self.audition_events:
            self.stop_notes()
            self.audition_hint.setText("试听序列已结束，请记录听感；不代表验收通过。")
            self.connection_changed()
            return
        ons, offs, delay, label = self.audition_events.pop(0)
        try:
            for note in offs:
                self.session.note(note, False)
                self.pressed_notes.discard(note)
            for note in ons:
                self.session.note(note, True)
                self.pressed_notes.add(note)
        except (RuntimeError, OSError) as exc:
            self.stop_notes()
            self.log_message("试听", str(exc))
            return
        self.audition_hint.setText(f"试听中：{label}；点“全部松键”可停止。")
        self.connection_changed()
        self.audition_timer.start(delay)

    def focus_changed(self, state):
        if state != Qt.ApplicationActive and (self.pressed_notes or self.audition_active):
            self.stop_notes()

    def log_message(self, kind, text):
        self.log_view.appendPlainText(f"{datetime.now():%H:%M:%S}  [{kind}] {text}")

    def problem(self, title, exc):
        self.log_message("错误", str(exc))
        if not self.test_mode:
            QMessageBox.warning(self, title, str(exc))

    def show_help(self):
        QMessageBox.information(self, "使用说明", "1. 拖动谐波柱，设置包络，保存配置。\n"
            "2. 选择模拟设备，点击连接，再点击应用到设备。\n"
            "3. 设备实验可观察音符与声部状态，模拟设备不发声。\n"
            "4. 双音色固件连接后，在演奏台选择钢琴／摇滚；等待设备确认即可演奏。\n\n"
            "详细说明：host/README.md")

    def closeEvent(self, event):
        if not self.confirm_discard():
            event.ignore()
            return
        try:
            self.stop_notes()
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
