"""Reproduce the redesign screenshots without opening any physical serial port."""
import os
from pathlib import Path
import sys
import time

os.environ["QT_QPA_PLATFORM"] = "offscreen"
ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "fpga_music_tool"))
from PySide6.QtWidgets import QApplication, QTabWidget
from PySide6.QtTest import QTest
from studio import StudioWindow, configure_fonts


def wait_for(condition):
    deadline = time.monotonic() + 2
    while not condition():
        if time.monotonic() > deadline:
            raise AssertionError("UI simulation timed out")
        QTest.qWait(10)


app = QApplication([])
app.setStyle("Fusion")
configure_fonts()
window = StudioWindow()
window.test_mode = True
window.show()
QTest.qWait(30)
window.grab().save(str(OUT / "disconnected.png"))
window.toggle_connection()
wait_for(lambda: window.session.ready)
window.choose_preset(2)
window.preset_combo.setCurrentIndex(2)
window.tone.name = "明亮 · 谐波练习"
window.render_tone()
window.apply()
wait_for(lambda: window.session.applied is not None)
window.grab().save(str(OUT / "design.png"))
tabs = window.findChild(QTabWidget)
tabs.setCurrentIndex(1)
QTest.qWait(30)
window.grab().save(str(OUT / "modulation.png"))
tabs.setCurrentIndex(0)
window.navigate(1)
QTest.qWait(30)
window.grab().save(str(OUT / "play.png"))
window.navigate(2)
QTest.qWait(50)
window.grab().save(str(OUT / "device.png"))
window.navigate(0)
window.resize(1100, 760)
QTest.qWait(30)
assert window.width() == 1100 and window.height() == 760
window.grab().save(str(OUT / "compact.png"))
window.close()
print("Rendered 6 screenshots: default, editor, modulation, keyboard, device, compact.")
