"""Visual layer for the tone studio: a dark, instrument-focused workspace."""
import os
from pathlib import Path

from PySide6.QtCore import Qt, QPointF, QRectF, Signal
from PySide6.QtGui import QColor, QFont, QFontDatabase, QLinearGradient, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import (
    QApplication, QAbstractSpinBox, QButtonGroup, QCheckBox, QComboBox, QFrame,
    QGridLayout, QHBoxLayout, QLabel, QLineEdit, QPlainTextEdit, QPushButton,
    QScrollArea, QSizePolicy, QSlider, QSpinBox, QStackedWidget, QTabWidget,
    QVBoxLayout, QWidget,
)
from studio_model import Tone, PARAMETERS, cycle_samples

INK = "#edf1e9"
MUTED = "#a1b0b4"
ACCENT = "#d5ed99"
WAVE = "#98d6c2"


def configure_fonts():
    if not QFontDatabase.families():
        font_dir = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
        for name in ["msyh.ttc", "msyhbd.ttc", "segoeui.ttf", "consola.ttf"]:
            if (font_dir / name).exists():
                QFontDatabase.addApplicationFont(str(font_dir / name))
    QApplication.instance().setFont(QFont("Microsoft YaHei", 10))


STYLE = """
QWidget { color:#edf1e9; font-family:'Microsoft YaHei'; font-size:13px; }
QMainWindow, QWidget#canvas { background:#101719; }
QFrame#header { background:#101719; border-bottom:1px solid #2b3538; }
QFrame#documentBar { background:#101719; }
QFrame#footer { background:#172023; border-top:1px solid #344145; }
QFrame#card { background:#192326; border:1px solid #303e42; border-radius:14px; }
QFrame#parameter { background:#121b1e; border:1px solid #2a393d; border-radius:8px; }
QFrame#metric { background:#121b1e; border:1px solid #2a393d; border-radius:10px; }
QLabel#brand { font-size:25px; font-weight:700; letter-spacing:3px; }
QLabel#title { font-size:24px; font-weight:600; }
QLabel#subtitle { color:#a1b0b4; font-size:12px; }
QLabel#eyebrow { color:#91a6aa; font-family:'Consolas'; font-size:11px; letter-spacing:2px; }
QLabel#cardTitle { font-size:16px; font-weight:600; }
QLabel#accent { color:#d5ed99; font-size:12px; }
QLabel#badge { background:#202b2e; color:#b2c0c1; border:1px solid #405055;
    border-radius:13px; padding:5px 12px; font-size:12px; }
QLabel#badge[ready="true"] { background:#26362b; color:#d5ed99; border-color:#506548; }
QLabel#metricValue { font-family:'Consolas'; font-size:34px; color:#d5ed99; }
QLabel#documentStatus { color:#aabcae; font-size:12px; }
QLineEdit, QSpinBox, QComboBox { background:#121b1e; border:1px solid #3b4a4e;
    border-radius:6px; padding:7px 10px; selection-background-color:#d5ed99;
    selection-color:#162020; min-height:18px; }
QLineEdit:focus, QSpinBox:focus, QComboBox:focus { border-color:#d5ed99; }
QLineEdit#toneName { background:transparent; border:0; border-bottom:1px solid #3b4a4e;
    border-radius:0; font-size:24px; font-weight:600; padding:3px 0 5px 0; }
QSpinBox#largeValue { font-family:'Consolas'; font-size:21px; background:transparent;
    border:0; padding:0; min-height:26px; }
QComboBox::drop-down { border:0; width:23px; }
QComboBox QAbstractItemView { background:#1e2b2f; color:#edf1e9;
    border:1px solid #3b4a4e; selection-background-color:#354c44; }
QPushButton { background:#233136; border:1px solid #3b4a4e; border-radius:7px;
    padding:8px 15px; font-size:12px; }
QPushButton:hover { background:#30413e; border-color:#79927b; }
QPushButton:pressed { background:#3b5546; }
QPushButton:focus { border-color:#d5ed99; }
QPushButton:disabled { color:#748488; background:#1d292d; border-color:#2e3a3e; }
QPushButton#primary { background:#d5ed99; color:#18221c; border-color:#d5ed99; font-weight:700; }
QPushButton#primary:hover { background:#e0f5b3; }
QPushButton#primary:disabled { background:#39493c; color:#afc19a; border-color:#4c5d48; }
QPushButton#ghost { background:transparent; border:1px solid transparent; color:#c3ceca; }
QPushButton#ghost:hover { background:#233136; border-color:#3b4a4e; }
QPushButton#nav { background:transparent; color:#9fadb0; border:0; border-radius:6px;
    padding:10px 24px; font-size:14px; }
QPushButton#nav:checked { color:#e8f4d1; background:#263a31; }
QPushButton#mode { padding:7px 10px; background:#121b1e; }
QPushButton#mode:checked { border-color:#9bae80; color:#d5ed99; background:#263a31; }
QTabWidget::pane { border:0; }
QTabBar::tab { padding:8px 18px; color:#a1b0b4; border-bottom:2px solid #304044; }
QTabBar::tab:selected { color:#d5ed99; border-bottom:2px solid #d5ed99; }
QTabBar::tab:hover { background:#22312f; }
QScrollArea { border:0; background:transparent; }
QScrollBar:vertical { width:8px; background:#101719; }
QScrollBar::handle:vertical { background:#45575a; border-radius:4px; min-height:35px; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height:0; }
QPlainTextEdit { background:#0d1417; color:#b9d5c4; border:1px solid #35454b;
    font-family:'Consolas'; font-size:12px; padding:8px; }
QSlider::groove:horizontal { height:4px; background:#344447; border-radius:2px; }
QSlider::sub-page:horizontal { background:#aabe89; border-radius:2px; }
QSlider::handle:horizontal { background:#d5ed99; width:10px; margin:-4px 0; border-radius:5px; }
QCheckBox { color:#a1b0b4; font-size:12px; spacing:7px; }
QCheckBox::indicator { width:12px; height:12px; border:1px solid #647673; border-radius:3px; }
QCheckBox::indicator:checked { background:#d5ed99; border-color:#d5ed99; }
QToolTip { background:#edf1e9; color:#172023; border:0; padding:5px; }
QMessageBox { background:#192326; }
"""


def label(text, role=None, wrap=False):
    item = QLabel(text)
    if role:
        item.setObjectName(role)
    item.setWordWrap(wrap)
    return item


def button(text, callback, role=None):
    item = QPushButton(text)
    if role:
        item.setObjectName(role)
    item.clicked.connect(callback)
    item.setCursor(Qt.PointingHandCursor)
    item.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
    return item


def card(title, eyebrow=None):
    frame = QFrame()
    frame.setObjectName("card")
    layout = QVBoxLayout(frame)
    layout.setContentsMargins(20, 17, 20, 18)
    layout.setSpacing(12)
    heading = QHBoxLayout()
    heading.addWidget(label(title, "cardTitle"))
    heading.addStretch()
    if eyebrow:
        heading.addWidget(label(eyebrow, "eyebrow"))
    layout.addLayout(heading)
    return frame, layout


class BrandMark(QWidget):
    def __init__(self):
        super().__init__()
        self.setFixedSize(39, 39)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(ACCENT))
        p.drawRoundedRect(QRectF(0, 0, 39, 39), 10, 10)
        p.setPen(QPen(QColor("#1c2b25"), 2.1, Qt.SolidLine, Qt.RoundCap))
        for i, height in enumerate([8, 18, 27, 14, 6]):
            x = 8 + i * 5.7
            p.drawLine(QPointF(x, 19.5 - height / 2), QPointF(x, 19.5 + height / 2))


class HarmonicEditor(QWidget):
    edited = Signal(int, int)
    selected = Signal(int)

    def __init__(self):
        super().__init__()
        self.values = [255] + [0] * 15
        self.index = 0
        self.setMinimumHeight(172)
        self.setMinimumWidth(380)
        self.setFocusPolicy(Qt.StrongFocus)
        self.setCursor(Qt.CrossCursor)
        self.setAccessibleName("16个谐波幅度；左右选择，上下调整，Shift加速")
        self.setToolTip("拖动绘制 · 左右选择 · 上下微调 · Shift 加速")

    def plot_rect(self):
        return QRectF(34, 28, self.width() - 44, self.height() - 53)

    def set_values(self, values):
        self.values = list(values)
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        rect = self.plot_rect()
        p.setFont(QFont("Consolas", 8))
        for value in [0, 128, 255]:
            y = rect.bottom() - rect.height() * value / 255
            p.setPen(QPen(QColor("#344448"), 1, Qt.DotLine))
            p.drawLine(QPointF(rect.left(), y), QPointF(rect.right(), y))
            p.setPen(QColor(MUTED))
            p.drawText(QRectF(0, y - 8, 26, 16), Qt.AlignRight | Qt.AlignVCenter, str(value))
        step = rect.width() / 16
        for i, value in enumerate(self.values):
            area = QRectF(rect.left() + i * step + step * .23, rect.top(), step * .54, rect.height())
            p.setPen(Qt.NoPen)
            p.setBrush(QColor("#253438"))
            p.drawRoundedRect(area, 3, 3)
            height = max(3, area.height() * value / 255)
            p.setBrush(QColor(ACCENT if i == self.index else "#709b8b"))
            p.drawRoundedRect(QRectF(area.left(), area.bottom() - height, area.width(), height), 3, 3)
            if i == self.index:
                p.setBrush(Qt.NoBrush)
                p.setPen(QPen(QColor("#829b72"), 1))
                p.drawRoundedRect(area.adjusted(-4, -4, 4, 4), 5, 5)
                p.setPen(Qt.NoPen)
                p.setBrush(QColor(ACCENT))
                badge = QRectF(area.center().x() - 17, 1, 34, 18)
                p.drawRoundedRect(badge, 4, 4)
                p.setPen(QColor("#172023"))
                p.drawText(badge, Qt.AlignCenter, str(value))
            p.setPen(QColor(ACCENT if i == self.index else MUTED))
            p.drawText(QRectF(area.center().x() - 16, rect.bottom() + 7, 32, 18),
                       Qt.AlignCenter, f"{i + 1:02d}")

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
            value = max(0, min(255, self.values[self.index] + (step if event.key() == Qt.Key_Up else -step)))
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
        self.setMinimumHeight(113 if envelope else 176)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

    def set_tone(self, tone):
        self.tone = tone.copy()
        self.tone.name = self.tone.name.strip() or "未命名"
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor("#101a1d"))
        p.drawRoundedRect(QRectF(self.rect()).adjusted(0, 0, -1, -1), 9, 9)
        rect = QRectF(19, 23, self.width() - 38, self.height() - 48)
        for i in range(5):
            p.setPen(QPen(QColor("#243437"), 1))
            x = rect.left() + i * rect.width() / 4
            p.drawLine(QPointF(x, rect.top()), QPointF(x, rect.bottom()))
            y = rect.top() + i * rect.height() / 4
            p.drawLine(QPointF(rect.left(), y), QPointF(rect.right(), y))
        path = QPainterPath()
        color = "#d8c5a5" if self.envelope else WAVE
        if self.envelope:
            positions = [0, .18, .44, .74, 1]
            sustain = self.tone.sustain / 255
            values = [0, 1, sustain, sustain, 0]
            if self.tone.mode == 1:
                values = [0, 1, 0, 0, 0]
            for i, (x, y) in enumerate(zip(positions, values)):
                point = QPointF(rect.left() + x * rect.width(), rect.bottom() - y * rect.height())
                path.moveTo(point) if i == 0 else path.lineTo(point)
            p.setFont(QFont("Consolas", 8))
            p.setPen(QColor(MUTED))
            for i, text in enumerate(["A", "D", "S", "R"]):
                p.drawText(QRectF(rect.left() + i * rect.width() / 4, rect.bottom() + 7,
                                 rect.width() / 4, 16), Qt.AlignCenter, text)
        else:
            samples = cycle_samples(self.tone, 512)
            for i, value in enumerate(samples):
                point = QPointF(rect.left() + i / 511 * rect.width(),
                                rect.center().y() - value * rect.height() * .45)
                path.moveTo(point) if i == 0 else path.lineTo(point)
            p.setPen(QColor(MUTED))
            p.setFont(QFont("Consolas", 8))
            p.drawText(QRectF(18, self.height() - 20, 100, 16), "0")
            p.drawText(QRectF(self.width() - 118, self.height() - 20, 100, 16), Qt.AlignRight, "1 CYCLE")
        fill = QPainterPath(path)
        fill.lineTo(rect.bottomRight())
        fill.lineTo(rect.bottomLeft())
        fill.closeSubpath()
        gradient = QLinearGradient(rect.topLeft(), rect.bottomLeft())
        top = QColor(color)
        top.setAlpha(48)
        bottom = QColor(color)
        bottom.setAlpha(0)
        gradient.setColorAt(0, top)
        gradient.setColorAt(1, bottom)
        p.fillPath(fill, gradient)
        p.setPen(QPen(QColor(color), 2.2, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        p.drawPath(path)


class PianoKey(QPushButton):
    def __init__(self, note, text, black=False, parent=None):
        super().__init__(text, parent)
        self.note, self.black = note, black
        self.setAccessibleName(f"音符 {text}")
        self.setCursor(Qt.PointingHandCursor)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        active = self.isDown()
        rect = QRectF(self.rect()).adjusted(1, 0, -2, -1)
        color = ACCENT if active else "#233237" if self.black else "#e5e7df"
        if not self.isEnabled():
            color = "#263135" if self.black else "#b2bcb4"
        p.setPen(QPen(QColor("#111b1e"), 1))
        p.setBrush(QColor(color))
        p.drawRoundedRect(rect, 5, 5)
        p.setPen(QPen(QColor("#556566" if self.black else "#a1aaa2"), 2))
        p.drawLine(QPointF(rect.left() + 4, rect.bottom() - 6), QPointF(rect.right() - 4, rect.bottom() - 6))
        p.setPen(QColor("#1a3027" if active or not self.black else "#bccbc7"))
        p.setFont(QFont("Consolas", 10))
        p.drawText(QRectF(0, self.height() - 36, self.width(), 22), Qt.AlignCenter, self.text())


class PianoKeyboard(QWidget):
    WHITE = [60, 62, 64, 65, 67, 69, 71, 72]
    BLACK = {61: 1, 63: 2, 66: 4, 68: 5, 70: 6}

    def __init__(self):
        super().__init__()
        self.setMinimumHeight(225)
        names = ["C4", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B", "C5"]
        self.keys = [PianoKey(60 + i, name, 60 + i in self.BLACK, self) for i, name in enumerate(names)]
        for note in self.BLACK:
            self.keys[note - 60].raise_()

    def resizeEvent(self, event):
        width = self.width() / 8
        for i, note in enumerate(self.WHITE):
            self.keys[note - 60].setGeometry(round(i * width), 0, round(width) + 1, self.height())
        for note, boundary in self.BLACK.items():
            key = self.keys[note - 60]
            key.setGeometry(round(boundary * width - width * .29), 0, round(width * .58), round(self.height() * .62))
            key.raise_()
        super().resizeEvent(event)


class StudioViewMixin:
    """Builds widgets; file/connection logic stays in StudioWindow."""
    def _build(self):
        root = QWidget()
        root.setObjectName("canvas")
        self.setCentralWidget(root)
        work = QVBoxLayout(root)
        work.setContentsMargins(0, 0, 0, 0)
        work.setSpacing(0)
        header = QFrame()
        header.setObjectName("header")
        head = QHBoxLayout(header)
        head.setContentsMargins(26, 17, 26, 17)
        head.setSpacing(14)
        head.addWidget(BrandMark())
        brand = QVBoxLayout()
        brand.setSpacing(0)
        brand.addWidget(label("声场", "brand"))
        brand.addWidget(label("FPGA SYNTH STUDIO", "eyebrow"))
        head.addLayout(brand)
        head.addStretch()
        self.nav_group = QButtonGroup(self)
        for i, title in enumerate(["音色工作台", "演奏", "设备"]):
            nav = button(title, lambda checked=False, n=i: self.navigate(n), "nav")
            nav.setCheckable(True)
            self.nav_group.addButton(nav, i)
            head.addWidget(nav)
        self.nav_group.button(0).setChecked(True)
        head.addStretch()
        self.connection_label = label("未连接", "badge")
        head.addWidget(self.connection_label)
        head.addWidget(button("帮助", self.show_help, "ghost"))
        work.addWidget(header)

        document = QFrame()
        document.setObjectName("documentBar")
        doc = QHBoxLayout(document)
        doc.setContentsMargins(28, 14, 28, 10)
        doc.setSpacing(12)
        title = QVBoxLayout()
        title.setSpacing(5)
        self.name_edit = QLineEdit()
        self.name_edit.setObjectName("toneName")
        self.name_edit.setMaxLength(80)
        self.name_edit.setMinimumWidth(240)
        self.name_edit.setMaximumWidth(380)
        self.name_edit.textEdited.connect(self.name_changed)
        title.addWidget(self.name_edit)
        self.document_label = label("", "documentStatus")
        title.addWidget(self.document_label)
        doc.addLayout(title)
        doc.addStretch(1)
        for text, callback, role in [("＋ 新建", self.new, "ghost"), ("打开音色", self.load, None),
                                     ("另存为", self.save_as, "ghost"), ("保存", self.save, None)]:
            doc.addWidget(button(text, callback, role))
        work.addWidget(document)

        self.pages = QStackedWidget()
        self.pages.addWidget(self.design_page())
        self.pages.addWidget(self.experiment_page())
        self.pages.addWidget(self.diagnostic_page())
        work.addWidget(self.pages, 1)
        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMaximumBlockCount(600)
        self.log_view.setMaximumHeight(140)
        self.log_view.hide()
        work.addWidget(self.log_view)

        footer = QFrame()
        footer.setObjectName("footer")
        foot = QVBoxLayout(footer)
        foot.setContentsMargins(27, 12, 27, 12)
        foot.setSpacing(9)
        row = QHBoxLayout()
        row.setSpacing(9)
        row.addWidget(label("设备", "subtitle"))
        self.port_combo = QComboBox()
        self.port_combo.setMinimumWidth(208)
        self.port_combo.setMaximumWidth(290)
        self.port_combo.setSizeAdjustPolicy(QComboBox.AdjustToMinimumContentsLengthWithIcon)
        self.port_combo.setMinimumContentsLength(18)
        row.addWidget(self.port_combo)
        self.baud_combo = QComboBox()
        self.baud_combo.addItems(["115200", "230400", "460800", "921600"])
        self.baud_combo.setFixedWidth(106)
        row.addWidget(self.baud_combo)
        self.refresh_button = button("刷新", self.refresh_ports, "ghost")
        row.addWidget(self.refresh_button)
        self.connect_button = button("连接", self.toggle_connection)
        row.addWidget(self.connect_button)
        row.addStretch()
        row.addWidget(button("导出波表", self.export_table, "ghost"))
        self.apply_button = button("应用到设备  →", self.apply, "primary")
        self.apply_button.setMinimumWidth(160)
        row.addWidget(self.apply_button)
        foot.addLayout(row)
        status = QHBoxLayout()
        self.file_label = label("", "subtitle")
        self.file_label.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        status.addWidget(self.file_label, 1)
        self.traffic_label = label("已发 0 B · 已收 0 B", "subtitle")
        status.addWidget(self.traffic_label)
        status.addSpacing(18)
        self.log_toggle = QCheckBox("通信日志")
        self.log_toggle.toggled.connect(self.log_view.setVisible)
        status.addWidget(self.log_toggle)
        foot.addLayout(status)
        work.addWidget(footer)

    def scroll_page(self, title=None, subtitle=None):
        area = QScrollArea()
        area.setWidgetResizable(True)
        area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        page = QWidget()
        page.setObjectName("canvas")
        layout = QVBoxLayout(page)
        layout.setContentsMargins(27, 10, 27, 20)
        layout.setSpacing(15)
        if title:
            layout.addWidget(label(title, "title"))
        if subtitle:
            layout.addWidget(label(subtitle, "subtitle", True))
        area.setWidget(page)
        return area, layout

    def design_page(self):
        area, layout = self.scroll_page()
        row = QHBoxLayout()
        row.setSpacing(18)
        oscillator, content = card("振荡器", "01 / OSCILLATOR")
        presets = QHBoxLayout()
        self.preset_combo = QComboBox()
        self.preset_combo.addItems(["纯正弦", "柔和草稿", "明亮草稿", "自定义"])
        self.preset_combo.activated.connect(self.choose_preset)
        presets.addWidget(self.preset_combo)
        presets.addStretch()
        presets.addWidget(label("单周期 · 峰值归一化", "subtitle"))
        content.addLayout(presets)
        self.wave = Curve()
        content.addWidget(self.wave, 1)
        caption = QHBoxLayout()
        caption.addWidget(label("谐波构成"))
        caption.addStretch()
        self.harmonic_count = label("01 / 16 启用", "eyebrow")
        caption.addWidget(self.harmonic_count)
        content.addLayout(caption)
        self.harmonics = HarmonicEditor()
        self.harmonics.selected.connect(self.select_harmonic)
        self.harmonics.edited.connect(self.edit_harmonic)
        content.addWidget(self.harmonics)
        exact = QHBoxLayout()
        self.harmonic_label = label("第 1 分量 · 基音", "accent")
        exact.addWidget(self.harmonic_label, 1)
        self.harmonic_spin = QSpinBox()
        self.harmonic_spin.setRange(0, 255)
        self.harmonic_spin.setSuffix(" / 255")
        self.harmonic_spin.setButtonSymbols(QAbstractSpinBox.NoButtons)
        self.harmonic_spin.setFixedWidth(110)
        self.harmonic_spin.valueChanged.connect(self.exact_harmonic)
        exact.addWidget(self.harmonic_spin)
        content.addLayout(exact)
        shapes = QHBoxLayout()
        for text, kind in [("正弦", "sine"), ("方波近似", "square"), ("锯齿近似", "saw"), ("清空", "zero")]:
            shapes.addWidget(button(text, lambda checked=False, k=kind: self.set_harmonics(k), "ghost"))
        content.addLayout(shapes)
        content.addWidget(label("拖动绘制 · 方向键微调 · Shift 加速", "subtitle"))
        row.addWidget(oscillator, 7)

        shaping, controls = card("动态塑形", "02 / SHAPING")
        self.parameter_spins = {}
        self.parameter_sliders = {}
        tabs = QTabWidget()
        envelope_page = QWidget()
        env = QVBoxLayout(envelope_page)
        env.setContentsMargins(0, 12, 0, 0)
        env.setSpacing(10)
        modes = QHBoxLayout()
        self.mode_group = QButtonGroup(self)
        for i, text in enumerate(["持续", "击发", "混合"]):
            item = button(text, lambda checked=False, n=i: self.parameter_changed("mode", n), "mode")
            item.setCheckable(True)
            item.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
            self.mode_group.addButton(item, i)
            modes.addWidget(item)
        env.addLayout(modes)
        self.mode_description = label("", "subtitle", True)
        env.addWidget(self.mode_description)
        self.envelope = Curve(envelope=True)
        env.addWidget(self.envelope)
        env.addWidget(label("起音 / 衰减 / 持续 / 释放 · 阶段示意", "subtitle"))
        grid = QGridLayout()
        grid.setSpacing(10)
        for i, (key, title, suffix) in enumerate([
            ("attack_ms", "A  起音", " ms"), ("decay_ms", "D  衰减", " ms"),
            ("sustain", "S  持续电平", " / 255"), ("release_ms", "R  释放", " ms"),
        ]):
            grid.addWidget(self.parameter_control(key, title, suffix), i // 2, i % 2)
        env.addLayout(grid)
        env.addStretch()
        tabs.addTab(envelope_page, "包络")
        modulation = QWidget()
        mod = QVBoxLayout(modulation)
        mod.setContentsMargins(0, 18, 0, 0)
        mod.setSpacing(16)
        mod.addWidget(label("颤音", "cardTitle"))
        mod.addWidget(label("让音高轻微、周期性地起伏。", "subtitle", True))
        mod.addWidget(self.parameter_control("vibrato_cents", "深度 · 0 为关闭", " 音分"))
        mod.addWidget(self.parameter_control("vibrato_tenths_hz", "速度 · 50 表示 5 Hz", " × 0.1 Hz"))
        mod.addWidget(label("实际声音需要 FPGA 固件支持。", "subtitle", True))
        mod.addStretch()
        tabs.addTab(modulation, "调制")
        controls.addWidget(tabs, 1)
        volume_row = QHBoxLayout()
        volume_row.addWidget(label("草稿音量 · 演奏音量请到“演奏”页调节"))
        volume_row.addStretch()
        volume = self.make_parameter("volume", " / 255")
        volume.setFixedWidth(115)
        volume_row.addWidget(volume)
        controls.addLayout(volume_row)
        controls.addWidget(self.make_slider("volume", volume))
        controls.addWidget(label("混响 / 延迟 / 合唱 · 尚未开放", "subtitle"))
        row.addWidget(shaping, 4)
        layout.addLayout(row, 1)
        return area

    def make_parameter(self, key, suffix):
        spin = QSpinBox()
        low, high, default = PARAMETERS[key]
        spin.setRange(low, high)
        spin.setValue(default)
        spin.setSuffix(suffix)
        spin.setButtonSymbols(QAbstractSpinBox.NoButtons)
        spin.setAccessibleName(key)
        spin.valueChanged.connect(lambda value, k=key: self.parameter_changed(k, value))
        self.parameter_spins[key] = spin
        return spin

    def make_slider(self, key, spin):
        slider = QSlider(Qt.Horizontal)
        slider.setRange(spin.minimum(), spin.maximum())
        slider.setValue(spin.value())
        slider.setAccessibleName(key + " 调节滑条")
        slider.valueChanged.connect(spin.setValue)
        spin.valueChanged.connect(slider.setValue)
        self.parameter_sliders[key] = slider
        return slider

    def parameter_control(self, key, title, suffix):
        frame = QFrame()
        frame.setObjectName("parameter")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(12, 9, 12, 11)
        layout.setSpacing(4)
        layout.addWidget(label(title, "subtitle"))
        spin = self.make_parameter(key, suffix)
        spin.setObjectName("largeValue")
        layout.addWidget(spin)
        layout.addWidget(self.make_slider(key, spin))
        return frame

    def experiment_page(self):
        area, layout = self.scroll_page("演奏台", "选择设备音色，按住琴键演奏。")
        frame, content = card("键盘", "C4 — C5 / 13 NOTES")
        instrument_row = QHBoxLayout()
        instrument_row.addWidget(label("设备音色"))
        self.device_preset_combo = QComboBox()
        self.device_preset_combo.addItem("钢琴", 1)
        self.device_preset_combo.addItem("摇滚电吉他", 0)
        self.device_preset_combo.setPlaceholderText("等待设备确认")
        self.device_preset_combo.setCurrentIndex(-1)
        self.device_preset_combo.activated.connect(self.choose_device_preset)
        instrument_row.addWidget(self.device_preset_combo)
        instrument_row.addWidget(label("新按下的音符使用所选音色，已有声音自然延续。", "subtitle", True))
        instrument_row.addStretch()
        content.addLayout(instrument_row)
        live = QHBoxLayout()
        live.addWidget(label("总音量"))
        self.device_volume = QSlider(Qt.Horizontal)
        self.device_volume.setRange(0, 127)
        self.device_volume.setValue(8)
        live.addWidget(self.device_volume, 1)
        live.addWidget(label("弯音 ±2 半音"))
        self.device_bend = QSlider(Qt.Horizontal)
        self.device_bend.setRange(-512, 512)
        self.device_bend.setValue(0)
        live.addWidget(self.device_bend, 1)
        self.center_bend_button = button("弯音归中", lambda: self.device_bend.setValue(0), "ghost")
        live.addWidget(self.center_bend_button)
        self.device_volume.valueChanged.connect(self.performance_edited)
        self.device_bend.valueChanged.connect(self.performance_edited)
        content.addLayout(live)
        self.control_hint = label("连接支持演奏控制的固件后启用。", "subtitle", True)
        content.addWidget(self.control_hint)
        self.play_hint = label("先连接设备并应用音色。", "accent", True)
        content.addWidget(self.play_hint)
        keyboard = PianoKeyboard()
        self.piano_buttons = keyboard.keys
        for key in keyboard.keys:
            key.pressed.connect(lambda n=key.note: self.note_pressed(n))
            key.released.connect(lambda n=key.note: self.note_released(n))
        content.addWidget(keyboard)
        actions = QHBoxLayout()
        self.chord_button = button("触发四音和弦", self.chord)
        self.power_button = button("五度和弦", self.power_chord)
        self.panic_button = button("全部松键", self.stop_notes, "ghost")
        actions.addWidget(self.chord_button)
        actions.addWidget(self.power_button)
        actions.addWidget(self.panic_button)
        actions.addStretch()
        actions.addWidget(label("按住演奏 / 松开释放", "subtitle"))
        content.addLayout(actions)
        auditions = QHBoxLayout()
        self.anchor_button = button("低中高音试听", lambda: self.start_audition("anchors"))
        self.scale_button = button("C3–C6 音阶扫描", lambda: self.start_audition("scale"))
        self.polyphony_button = button("16音测试", lambda: self.start_audition("polyphony"))
        for item in (self.anchor_button, self.scale_button, self.polyphony_button):
            auditions.addWidget(item)
        auditions.addStretch()
        content.addLayout(auditions)
        self.voice_hint = label("设备报告当前声部：—", "subtitle", True)
        content.addWidget(self.voice_hint)
        self.audition_hint = label("使用当前总音量；16音为压力测试。切换页面或窗口会停止自动试听。", "subtitle", True)
        content.addWidget(self.audition_hint)
        layout.addWidget(frame)
        hints = QHBoxLayout()
        hints.addWidget(label("声音由 FPGA 生成", "eyebrow"))
        hints.addStretch()
        hints.addWidget(label("模拟设备只验证交互，不产生声音。", "subtitle"))
        layout.addLayout(hints)
        layout.addStretch()
        return area

    def diagnostic_page(self):
        area, layout = self.scroll_page("设备中心", "连接状态与设备报告，集中查看。")
        row = QHBoxLayout()
        row.setSpacing(18)
        frame, content = card("设备状态", "DEVICE / TELEMETRY")
        self.device_info = label("未连接设备", "subtitle", True)
        content.addWidget(self.device_info)
        self.status_labels = {}
        grid = QGridLayout()
        grid.setSpacing(12)
        for i, (key, title) in enumerate([("VOICE_COUNT", "当前声部"), ("MAX_VOICE_COUNT", "峰值声部"),
                                         ("STEAL_COUNT", "抢占次数"), ("SAMPLE_RATE", "设备报告采样率")]):
            metric = QFrame()
            metric.setObjectName("metric")
            box = QVBoxLayout(metric)
            box.setContentsMargins(18, 17, 18, 17)
            box.setSpacing(12)
            box.addWidget(label(title, "subtitle"))
            value = label("—", "metricValue")
            box.addWidget(value)
            self.status_labels[key] = value
            grid.addWidget(metric, i // 2, i % 2)
        content.addLayout(grid)
        self.query_button = button("刷新设备状态", self.session.query_status)
        content.addWidget(self.query_button)
        content.addWidget(label("模拟状态或设备报告值，不等同于实物测量。", "subtitle", True))
        row.addWidget(frame, 3)
        guide, details = card("连接指南", "GET CONNECTED")
        for title, body in [
            ("01  选择设备", "在底部选择串口与波特率；也可以选择模拟设备试用。"),
            ("02  等待确认", "连接后由设备返回支持的功能；串口打开本身不代表固件就绪。"),
            ("03  确认能力", "双音色固件在演奏台选择钢琴／摇滚；可配置设备需先应用并等待确认。"),
        ]:
            details.addWidget(label(title))
            details.addWidget(label(body, "subtitle", True))
            details.addSpacing(8)
        details.addWidget(label("双音色固件支持预设切换；设计页的谐波、包络和音量草稿不会改变这些内置音色。", "accent", True))
        details.addStretch()
        row.addWidget(guide, 2)
        layout.addLayout(row)
        layout.addStretch()
        return area
