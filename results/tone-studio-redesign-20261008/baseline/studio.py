"""FPGA tone studio. Run with Python; --screenshot PATH renders a preview."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import sys

from PySide6.QtCore import Qt, QPointF, QRectF, QTimer, Signal
from PySide6.QtGui import QColor, QFont, QFontDatabase, QKeySequence, QPainter, QPainterPath, QPen, QShortcut
from PySide6.QtWidgets import (
    QApplication, QButtonGroup, QCheckBox, QComboBox, QFileDialog, QFrame,
    QGridLayout, QHBoxLayout, QLabel, QLineEdit, QMainWindow, QMessageBox,
    QPlainTextEdit, QPushButton, QScrollArea, QSlider, QSpinBox, QStackedWidget,
    QTabWidget, QVBoxLayout, QWidget,
)
from serial.tools import list_ports

from studio_model import Tone, PARAMETERS, cycle_samples, export_hex, harmonic_preset, load_tone, save_tone
from studio_transport import StudioSession


INK = "#2d2b27"
MUTED = "#80766a"
ACCENT = "#b4422c"


def configure_fonts():
    # Qt's offscreen Windows plugin has an empty font database by default.
    # Load installed fonts only; no font files are copied into the project.
    if not QFontDatabase.families():
        font_dir = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
        for name in ["msyh.ttc", "msyhbd.ttc", "segoeui.ttf", "consola.ttf"]:
            if (font_dir / name).exists():
                QFontDatabase.addApplicationFont(str(font_dir / name))
    QApplication.instance().setFont(QFont("Microsoft YaHei", 10))


STYLE = """
QWidget { color:#2d2b27; font-family:'Microsoft YaHei'; font-size:13px; }
QMainWindow, QWidget#canvas { background:#f3f0e9; }
QFrame#sidebar { background:#e7e1d6; border-right:1px solid #d9d0c3; }
QFrame#header, QFrame#footer { background:#fffdfa; }
QFrame#header { border-bottom:1px solid #dfd5c9; }
QFrame#footer { border-top:1px solid #dfd5c9; }
QFrame#card { background:#fffdfa; border:1px solid #dfd5c9; border-radius:12px; }
QLabel#title { font-size:26px; font-weight:700; }
QLabel#subtitle { color:#80766a; }
QLabel#cardTitle { color:#80766a; font-size:13px; font-weight:600; }
QLabel#accent { color:#b4422c; }
QLabel#badge { background:#ece7de; border-radius:5px; padding:6px 12px; color:#6b6257; }
QLineEdit, QSpinBox, QComboBox { background:#fffdfa; border:1px solid #ded2c5;
    border-radius:5px; padding:7px 9px; selection-background-color:#b4422c; }
QLineEdit:focus, QSpinBox:focus, QComboBox:focus { border:1px solid #b4422c; }
QLineEdit#toneName { font-size:18px; font-weight:600; }
QPushButton { background:#fffdfa; border:1px solid #dfd2c5; border-radius:6px; padding:8px 14px; }
QPushButton:hover { background:#f2e8de; border-color:#b4422c; }
QPushButton:pressed { background:#e4d4c5; }
QPushButton:disabled { color:#aea599; background:#f3efe9; border-color:#e7dfd5; }
QPushButton#primary { background:#b4422c; color:#fffdfa; border-color:#b4422c; font-weight:600; }
QPushButton#primary:hover { background:#983725; }
QPushButton#primary:disabled { background:#c5b5a9; border-color:#c5b5a9; }
QPushButton#nav { background:transparent; border:0; border-left:3px solid transparent;
    border-radius:6px; text-align:left; padding:14px 12px; font-size:15px; }
QPushButton#nav:checked { background:#fffdfa; color:#b4422c; border-left:3px solid #b4422c; font-weight:600; }
QPushButton#mode:checked { border-color:#b4422c; color:#b4422c; background:#fbf2eb; }
QPushButton#piano { padding:5px; border-radius:0 0 5px 5px; background:#fffdfa; }
QPushButton#piano:pressed { background:#b4422c; color:white; }
QTabWidget::pane { border:0; }
QTabBar::tab { padding:9px 12px; color:#80766a; border-bottom:2px solid #ddd3c7; }
QTabBar::tab:selected { color:#b4422c; border-bottom:2px solid #b4422c; }
QTabBar::tab:hover { background:#f3eee7; }
QScrollArea { border:0; background:transparent; }
QScrollBar:vertical { width:9px; background:#f3f0e9; }
QScrollBar::handle:vertical { background:#d8d0c3; border-radius:4px; min-height:30px; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height:0; }
QPlainTextEdit { background:#f8f5ee; border:1px solid #ddd3c7; border-radius:6px;
    font-family:Consolas; font-size:12px; padding:8px; }
QSlider::groove:horizontal { height:6px; background:#e8e1d7; border-radius:3px; }
QSlider::sub-page:horizontal { background:#b4422c; border-radius:3px; }
QSlider::handle:horizontal { background:#b4422c; width:14px; margin:-5px 0; border-radius:7px; }
QCheckBox { color:#80766a; }
"""


def label(text, role=None, wrap=False):
    result = QLabel(text)
    if role:
        result.setObjectName(role)
    result.setWordWrap(wrap)
    return result


def button(text, callback, role=None):
    result = QPushButton(text)
    if role:
        result.setObjectName(role)
    result.clicked.connect(callback)
    return result


def card(title):
    frame = QFrame()
    frame.setObjectName("card")
    layout = QVBoxLayout(frame)
    layout.setContentsMargins(16, 14, 16, 16)
    layout.setSpacing(10)
    layout.addWidget(label(title, "cardTitle"))
    return frame, layout


class HarmonicEditor(QWidget):
    edited = Signal(int, int)
    selected = Signal(int)

    def __init__(self):
        super().__init__()
        self.values = [255] + [0] * 15
        self.index = 0
        self.setMinimumHeight(228)
        self.setMinimumWidth(390)
        self.setFocusPolicy(Qt.StrongFocus)
        self.setAccessibleName("16个谐波幅度，左右选择，上下调整")
        self.setToolTip("拖动柱子改变幅度；左右键选择，上下键调节，Shift 加速")

    def plot_rect(self):
        return QRectF(35, 18, self.width() - 42, self.height() - 46)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        rect = self.plot_rect()
        p.setFont(QFont("Microsoft YaHei", 9))
        for v in [0, 64, 128, 191, 255]:
            y = rect.bottom() - rect.height() * v / 255
            p.setPen(QColor("#ece6dc"))
            p.drawLine(QPointF(rect.left(), y), QPointF(rect.right(), y))
            p.setPen(QColor(MUTED))
            p.drawText(QRectF(0, y - 9, 29, 18), Qt.AlignRight | Qt.AlignVCenter, str(v))
        step = rect.width() / 16
        for i, value in enumerate(self.values):
            area = QRectF(rect.left() + step * i + 2, rect.top(), step - 5, rect.height())
            p.setPen(Qt.NoPen)
            p.setBrush(QColor("#eee9e0"))
            p.drawRoundedRect(area, 3, 3)
            if value:
                fill = QRectF(area.left(), area.bottom() - area.height() * value / 255,
                              area.width(), area.height() * value / 255)
                p.setBrush(QColor(ACCENT if i == self.index else "#cc927d"))
                p.drawRoundedRect(fill, 2, 2)
            if i == self.index:
                p.setBrush(Qt.NoBrush)
                p.setPen(QPen(QColor(ACCENT), 1.5))
                p.drawRoundedRect(area.adjusted(-1, -1, 1, 1), 3, 3)
                p.setPen(QColor(INK))
                p.drawText(QRectF(area.left() - 3, rect.top() - 17, area.width() + 6, 16),
                           Qt.AlignCenter, str(value))
            p.setPen(QColor(MUTED))
            p.drawText(QRectF(area.left(), rect.bottom() + 5, area.width(), 20),
                       Qt.AlignCenter, str(i + 1))

    def set_values(self, values):
        self.values = list(values)
        self.update()

    def pick(self, pos):
        rect = self.plot_rect()
        self.index = max(0, min(15, int((pos.x() - rect.left()) / (rect.width() / 16))))
        value = max(0, min(255, round((rect.bottom() - pos.y()) / rect.height() * 255)))
        self.values[self.index] = value
        self.selected.emit(self.index)
        self.edited.emit(self.index, value)
        self.update()

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.setFocus()
            self.pick(event.position())

    def mouseMoveEvent(self, event):
        if event.buttons() & Qt.LeftButton:
            self.pick(event.position())

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key_Left, Qt.Key_Right):
            self.index = (self.index + (1 if event.key() == Qt.Key_Right else -1)) % 16
            self.selected.emit(self.index)
        elif event.key() in (Qt.Key_Up, Qt.Key_Down):
            step = 8 if event.modifiers() & Qt.ShiftModifier else 1
            delta = step if event.key() == Qt.Key_Up else -step
            value = max(0, min(255, self.values[self.index] + delta))
            self.values[self.index] = value
            self.edited.emit(self.index, value)
        else:
            super().keyPressEvent(event)
        self.update()


class Curve(QWidget):
    def __init__(self, envelope=False):
        super().__init__()
        self.envelope = envelope
        self.tone = Tone()
        self.setMinimumHeight(130 if envelope else 110)

    def set_tone(self, tone):
        self.tone = tone.copy()
        self.tone.name = self.tone.name.strip() or "未命名"
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        rect = QRectF(8, 14, self.width() - 16, self.height() - (37 if self.envelope else 25))
        p.setPen(QPen(QColor("#e4dbd0"), 1))
        p.drawLine(QPointF(rect.left(), rect.bottom()), QPointF(rect.right(), rect.bottom()))
        path = QPainterPath()
        if self.envelope:
            # This curve illustrates stages; horizontal lengths are not measured time.
            positions = [0, .18, .42, .74, 1]
            sustain = self.tone.sustain / 255
            points = [0, 1, sustain, sustain, 0]
            if self.tone.mode == 1:
                positions = [0, .18, .7, .7, 1]
                points = [0, 1, 0, 0, 0]
            for i, (x, y) in enumerate(zip(positions, points)):
                point = QPointF(rect.left() + x * rect.width(), rect.bottom() - y * rect.height())
                path.moveTo(point) if i == 0 else path.lineTo(point)
            p.setPen(QColor(MUTED))
            for i, text in enumerate(["起音", "衰减", "持续", "释放"]):
                p.drawText(QRectF(rect.left() + i * rect.width() / 4, rect.bottom() + 6,
                                 rect.width() / 4, 20), Qt.AlignCenter, text)
        else:
            samples = cycle_samples(self.tone, 512)
            p.setPen(QPen(QColor("#e4dbd0"), 1))
            p.drawLine(QPointF(rect.left(), rect.center().y()), QPointF(rect.right(), rect.center().y()))
            for i, value in enumerate(samples):
                point = QPointF(rect.left() + i / (len(samples) - 1) * rect.width(),
                                rect.center().y() - value * rect.height() * .44)
                path.moveTo(point) if i == 0 else path.lineTo(point)
        p.setPen(QPen(QColor(ACCENT), 2))
        p.drawPath(path)


class StudioWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("音色设计台 · FPGA 实时乐器")
        self.resize(1280, 860)
        self.setMinimumSize(1100, 700)
        self.setStyleSheet(STYLE)
        self.tone = Tone()
        self.file_path = None
        self.saved_document = None
        self.session = StudioSession(self)
        self.pressed_notes = set()
        self.piano_buttons = []
        self.rendering = False
        self.test_mode = False
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

    def _build(self):
        root = QWidget()
        root.setObjectName("canvas")
        outer = QHBoxLayout(root)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        self.setCentralWidget(root)
        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(210)
        side = QVBoxLayout(sidebar)
        side.setContentsMargins(18, 28, 16, 20)
        side.setSpacing(12)
        side.addWidget(label("音色设计", "title"))
        side.addWidget(label("绘制分量，编辑参数\n保存和载入完整配置", "subtitle"))
        side.addSpacing(20)
        self.nav_group = QButtonGroup(self)
        for i, title in enumerate(["音色设计", "设备实验", "硬件诊断"]):
            nav = button(f"0{i + 1}     {title}", lambda checked=False, n=i: self.navigate(n), "nav")
            nav.setCheckable(True)
            self.nav_group.addButton(nav, i)
            side.addWidget(nav)
        self.nav_group.button(0).setChecked(True)
        side.addStretch()
        side.addWidget(label("声音由 FPGA 生成\n此处编辑与发送参数", "subtitle"))
        side.addSpacing(8)
        side.addWidget(button("使用说明", self.show_help))
        outer.addWidget(sidebar)
        workspace = QWidget()
        work = QVBoxLayout(workspace)
        work.setContentsMargins(0, 0, 0, 0)
        work.setSpacing(0)
        header = QFrame()
        header.setObjectName("header")
        head = QVBoxLayout(header)
        head.setContentsMargins(24, 14, 24, 12)
        head.setSpacing(7)
        actions = QHBoxLayout()
        self.name_edit = QLineEdit()
        self.name_edit.setObjectName("toneName")
        self.name_edit.setMaxLength(80)
        self.name_edit.textEdited.connect(self.name_changed)
        actions.addWidget(self.name_edit, 1)
        for text, callback, role in [("新建", self.new, None), ("载入…", self.load, None),
                                     ("保存", self.save, "primary"), ("另存为…", self.save_as, None)]:
            actions.addWidget(button(text, callback, role))
        head.addLayout(actions)
        self.document_label = label("", "accent")
        self.file_label = label("", "subtitle")
        head.addWidget(self.document_label)
        head.addWidget(self.file_label)
        work.addWidget(header)
        self.pages = QStackedWidget()
        self.pages.addWidget(self.design_page())
        self.pages.addWidget(self.experiment_page())
        self.pages.addWidget(self.diagnostic_page())
        work.addWidget(self.pages, 1)
        toggle_row = QHBoxLayout()
        toggle_row.setContentsMargins(24, 0, 24, 5)
        self.log_toggle = QCheckBox("显示设备操作日志")
        self.log_toggle.toggled.connect(lambda visible: self.log_view.setVisible(visible))
        toggle_row.addWidget(self.log_toggle)
        toggle_row.addStretch()
        work.addLayout(toggle_row)
        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMaximumBlockCount(600)
        self.log_view.setMaximumHeight(140)
        self.log_view.hide()
        work.addWidget(self.log_view)
        footer = QFrame()
        footer.setObjectName("footer")
        foot = QVBoxLayout(footer)
        foot.setContentsMargins(16, 10, 24, 10)
        self.port_combo = QComboBox()
        self.port_combo.setMinimumWidth(210)
        self.baud_combo = QComboBox()
        self.baud_combo.addItems(["115200", "230400", "460800", "921600"])
        self.connect_button = button("连接", self.toggle_connection, "primary")
        self.refresh_button = button("刷新端口", self.refresh_ports)
        self.connection_label = label("未连接", "badge")
        row = QHBoxLayout()
        row.addWidget(label("端口"))
        row.addWidget(self.port_combo)
        row.addWidget(self.baud_combo)
        row.addWidget(self.refresh_button)
        row.addWidget(self.connect_button)
        row.addWidget(self.connection_label)
        row.addStretch()
        foot.addLayout(row)
        second = QHBoxLayout()
        self.traffic_label = label("已发 0 B · 已收 0 B", "accent")
        second.addWidget(self.traffic_label)
        second.addStretch()
        second.addWidget(button("导出单周期波表…", self.export_table))
        self.apply_button = button("应用到设备", self.apply, "primary")
        second.addWidget(self.apply_button)
        foot.addLayout(second)
        work.addWidget(footer)
        outer.addWidget(workspace, 1)

    def scroll_page(self, title, subtitle):
        area = QScrollArea()
        area.setWidgetResizable(True)
        area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        page = QWidget()
        page.setObjectName("canvas")
        layout = QVBoxLayout(page)
        layout.setContentsMargins(24, 18, 24, 22)
        layout.setSpacing(10)
        layout.addWidget(label(title, "title"))
        layout.addWidget(label(subtitle, "subtitle", True))
        area.setWidget(page)
        return area, layout

    def design_page(self):
        area, layout = self.scroll_page("音色设计", "绘制声音的分量，设定它如何开始、延续与消退。")
        row = QHBoxLayout()
        row.setSpacing(16)
        left, content = card("01  /  声音的构成")
        preset_row = QHBoxLayout()
        preset_row.addWidget(label("预设"))
        self.preset_combo = QComboBox()
        self.preset_combo.addItems(["纯正弦", "柔和草稿", "明亮草稿", "自定义"])
        self.preset_combo.activated.connect(self.choose_preset)
        preset_row.addWidget(self.preset_combo, 1)
        preset_row.addWidget(label("16 个谐波分量", "subtitle"))
        content.addLayout(preset_row)
        self.harmonics = HarmonicEditor()
        self.harmonics.selected.connect(self.select_harmonic)
        self.harmonics.edited.connect(self.edit_harmonic)
        content.addWidget(self.harmonics)
        exact = QHBoxLayout()
        self.harmonic_label = label("第 1 分量 · 基音")
        exact.addWidget(self.harmonic_label, 1)
        self.harmonic_spin = QSpinBox()
        self.harmonic_spin.setRange(0, 255)
        self.harmonic_spin.setSuffix(" / 255")
        self.harmonic_spin.valueChanged.connect(self.exact_harmonic)
        exact.addWidget(self.harmonic_spin)
        content.addLayout(exact)
        presets = QHBoxLayout()
        for title, kind in [("正弦", "sine"), ("方波近似", "square"), ("锯齿近似", "saw"), ("全零", "zero")]:
            presets.addWidget(button(title, lambda checked=False, k=kind: self.set_harmonics(k)))
        content.addLayout(presets)
        content.addWidget(label("拖动绘谱，或选中分量精确输入；方向键微调，Shift 加速。", "subtitle", True))
        self.wave = Curve()
        content.addWidget(self.wave)
        content.addWidget(label("单周期形状预览 · 合成后按峰值归一化", "subtitle"))
        content.addStretch()
        row.addWidget(left, 6)
        right, controls = card("02  /  声音的性格")
        tabs = QTabWidget()
        envelope_page = QWidget()
        envelope_layout = QVBoxLayout(envelope_page)
        envelope_layout.setContentsMargins(0, 10, 0, 0)
        modes = QHBoxLayout()
        self.mode_group = QButtonGroup(self)
        for i, text in enumerate(["持续", "击发", "混合"]):
            control = button(text, lambda checked=False, n=i: self.parameter_changed("mode", n), "mode")
            control.setCheckable(True)
            self.mode_group.addButton(control, i)
            modes.addWidget(control)
        envelope_layout.addLayout(modes)
        self.mode_description = label("", "subtitle", True)
        envelope_layout.addWidget(self.mode_description)
        self.envelope = Curve(envelope=True)
        envelope_layout.addWidget(self.envelope)
        envelope_layout.addWidget(label("包络阶段示意，不按时间比例绘制。", "subtitle"))
        self.parameter_spins = {}
        grid = QGridLayout()
        for n, (key, title, suffix) in enumerate([
            ("attack_ms", "起音时间", " ms"), ("decay_ms", "衰减时间", " ms"),
            ("sustain", "持续电平", " / 255"), ("release_ms", "释放时间", " ms"),
            ("volume", "主音量", " / 255"),
        ]):
            grid.addWidget(label(title), n, 0)
            spin = self.make_parameter(key, suffix)
            grid.addWidget(spin, n, 1)
        envelope_layout.addLayout(grid)
        envelope_layout.addStretch()
        tabs.addTab(envelope_page, "发声方式")
        vibrato_page = QWidget()
        vibrato_layout = QVBoxLayout(vibrato_page)
        vibrato_layout.setContentsMargins(0, 20, 0, 0)
        vibrato_layout.addWidget(label("让音高轻微、周期性地起伏。", "subtitle", True))
        for key, title, suffix in [("vibrato_cents", "颤音深度（0 为关闭）", " 音分"),
                                   ("vibrato_tenths_hz", "颤音速度（50 表示 5 Hz）", " × 0.1 Hz")]:
            vibrato_layout.addWidget(label(title))
            vibrato_layout.addWidget(self.make_parameter(key, suffix))
        vibrato_layout.addWidget(label("此处保存参数；实际效果需 FPGA 固件支持。", "subtitle", True))
        vibrato_layout.addStretch()
        tabs.addTab(vibrato_page, "颤音")
        effects_page = QWidget()
        effect_layout = QVBoxLayout(effects_page)
        effect_layout.setContentsMargins(0, 20, 0, 0)
        effect_layout.addWidget(label("效果器 · 后续拓展"))
        effect_layout.addWidget(label("当前版本先完成音色、包络和演奏控制。混响、延迟和合唱尚未接入。", "subtitle", True))
        for effect in ["混响", "延迟", "合唱"]:
            disabled = QPushButton(effect + "  /  待开发")
            disabled.setEnabled(False)
            effect_layout.addWidget(disabled)
        effect_layout.addStretch()
        tabs.addTab(effects_page, "效果器")
        controls.addWidget(tabs)
        row.addWidget(right, 5)
        layout.addLayout(row)
        layout.addStretch()
        return area

    def make_parameter(self, key, suffix):
        spin = QSpinBox()
        low, high, default = PARAMETERS[key]
        spin.setRange(low, high)
        spin.setValue(default)
        spin.setSuffix(suffix)
        spin.valueChanged.connect(lambda value, k=key: self.parameter_changed(k, value))
        self.parameter_spins[key] = spin
        return spin

    def experiment_page(self):
        area, layout = self.scroll_page("设备实验", "先应用音色，再按住琴键发送音符；模拟设备只展示控制过程。")
        frame, content = card("01  /  一个八度的演奏测试")
        self.play_hint = label("先连接设备并应用音色。", "accent", True)
        content.addWidget(self.play_hint)
        keys = QHBoxLayout()
        keys.setSpacing(4)
        names = ["C4", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B", "C5"]
        for i, name in enumerate(names):
            note = 60 + i
            key = QPushButton(name)
            key.setObjectName("piano")
            key.setMinimumHeight(160 if "♯" not in name else 110)
            key.setMinimumWidth(43)
            key.pressed.connect(lambda n=note: self.note_pressed(n))
            key.released.connect(lambda n=note: self.note_released(n))
            keys.addWidget(key, 1, Qt.AlignTop)
            self.piano_buttons.append(key)
        content.addLayout(keys)
        content.addWidget(label("鼠标按住发声、松开释放。支持多触发的设备可保留多个独立声部。", "subtitle", True))
        controls = QHBoxLayout()
        self.chord_button = button("触发四音和弦", self.chord)
        self.panic_button = button("全部松键", self.stop_notes)
        controls.addWidget(self.chord_button)
        controls.addWidget(self.panic_button)
        controls.addStretch()
        content.addLayout(controls)
        layout.addWidget(frame)
        info, details = card("02  /  检查什么")
        details.addWidget(label("观察声部数量，依次尝试单键、松键、和弦与全部松键。", wrap=True))
        details.addWidget(label("模拟数据用于验证界面与通信；不能作为复音、采样率或整机延迟的实物证据。", "subtitle", True))
        layout.addWidget(info)
        layout.addStretch()
        return area

    def diagnostic_page(self):
        area, layout = self.scroll_page("硬件诊断", "先确认通信，再检查设备返回的状态。")
        frame, content = card("01  /  连接与设备能力")
        self.device_info = label("未连接设备", wrap=True)
        content.addWidget(self.device_info)
        self.status_labels = {}
        grid = QGridLayout()
        for i, (key, title) in enumerate([("VOICE_COUNT", "当前声部"), ("MAX_VOICE_COUNT", "峰值声部"),
                                         ("STEAL_COUNT", "抢占次数"), ("SAMPLE_RATE", "设备报告采样率")]):
            grid.addWidget(label(title, "subtitle"), i, 0)
            value = label("—")
            value.setStyleSheet("font-size:20px; font-weight:600;")
            grid.addWidget(value, i, 1)
            self.status_labels[key] = value
        content.addLayout(grid)
        self.query_button = button("读取设备状态", self.session.query_status)
        content.addWidget(self.query_button)
        layout.addWidget(frame)
        guide, help_layout = card("02  /  为什么能烧录，却不能调参")
        help_layout.addWidget(label("烧录使用 JTAG 下载通道；调参需要 FPGA 程序额外实现 UART 收发、命令解析和可修改的参数。", wrap=True))
        help_layout.addWidget(label("当前项目的 instrument_adsr_top 尚无 UART 接口。串口能打开，也可能收不到设备确认。", "subtitle", True))
        help_layout.addWidget(label("连接后未确认：核对串口、波特率和固件；暂时可使用模拟设备试用界面。", "subtitle", True))
        layout.addWidget(guide)
        layout.addStretch()
        return area

    def navigate(self, index):
        if self.pages.currentIndex() == 1:
            self.stop_notes()
        self.pages.setCurrentIndex(index)
        self.nav_group.button(index).setChecked(True)

    def render_tone(self):
        self.rendering = True
        self.name_edit.setText(self.tone.name)
        self.harmonics.set_values(self.tone.harmonics)
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
        if self.session.pending:
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
        self.port_combo.addItem("【模拟设备】进程内测试", "SIM")
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
        self.traffic_label.setText(f"已发 {self.session.tx_bytes} B · 已收 {self.session.rx_bytes} B")
        playable = self.session.ready and "NOTES" in self.session.capabilities and self.session.applied is not None
        for key in self.piano_buttons:
            key.setEnabled(playable)
        maximum = int(self.session.device.get("MAX_VOICES", "0"))
        self.chord_button.setEnabled(playable and maximum >= 4)
        self.panic_button.setEnabled(self.session.ready and "NOTES" in self.session.capabilities)
        self.query_button.setEnabled(self.session.ready and "STATUS" in self.session.capabilities)
        self.play_hint.setText("模拟设备只显示音符事件，不产生声音。" if playable and self.session.simulated else
                               "按住琴键演奏。" if playable else "先连接支持演奏的设备并应用音色。")
        if self.session.ready:
            source = "模拟设备" if self.session.simulated else "真实设备报告"
            self.device_info.setText(f"{source} · 固件 {self.session.device.get('FW', '未提供')}\n"
                                     f"报告支持 {maximum} 声部 · 功能：{', '.join(sorted(self.session.capabilities))}")
        else:
            self.device_info.setText(self.session.label)
            self.pressed_notes.clear()
        self.update_document_status()

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
        try:
            self.session.note(note, True)
            self.pressed_notes.add(note)
        except RuntimeError as exc:
            self.log_message("提示", str(exc))

    def note_released(self, note):
        if note in self.pressed_notes:
            try:
                self.session.note(note, False)
            except RuntimeError as exc:
                self.log_message("提示", str(exc))
            self.pressed_notes.discard(note)

    def chord(self):
        self.stop_notes()
        for note in [60, 64, 67, 72]:
            self.note_pressed(note)

    def stop_notes(self):
        for note in list(self.pressed_notes):
            self.note_released(note)
        try:
            self.session.panic()
        except RuntimeError as exc:
            self.log_message("提示", str(exc))

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
        QMessageBox.information(self, "使用说明", "1. 拖动谐波柱，设置包络，保存配置。\n"
            "2. 选择模拟设备，点击连接，再点击应用到设备。\n"
            "3. 设备实验可观察音符与声部状态，模拟设备不发声。\n"
            "4. 真实设备需要 SYNTH/1 固件，当前板级程序尚未接入。\n\n"
            "详细说明：fpga_music_tool/STUDIO_README.md")

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
