"""Diagnostic used on the extracted EXE as well as source builds."""
import json
from pathlib import Path
import platform
import tempfile
import time

from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from studio_model import Tone, load_tone, save_tone
from studio_runtime import VERSION, release_info
from studio_transport import MockTransport


def wait_for(predicate, seconds=2):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        QApplication.processEvents()
        if predicate():
            return
        QTest.qWait(10)
    raise RuntimeError("诊断等待超时")


def run_self_check(window, destination):
    destination = Path(destination).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = {"ok": False, "version": VERSION, "platform": platform.platform(),
              "release": release_info(), "physical_serial_opened": False,
              "audio_generated": False, "checks": {}}
    window.test_mode = True  # Diagnostic-only: no modal error dialogs.
    try:
        window.start_demo()
        wait_for(lambda: window.session.ready)
        session = window.session
        if not isinstance(session.transport, MockTransport) or not session.demo_mode:
            raise RuntimeError("诊断必须只使用内存模拟器")
        result["maximum_voices"] = int(session.device["MAX_VOICES"])
        result["checks"]["handshake"] = result["maximum_voices"] == 32
        for note in range(48, 81):
            session.note(note, True)
        wait_for(lambda: session.status.get("STEAL_COUNT") == 1)
        result["checks"]["polyphony_and_steal"] = session.status["VOICE_COUNT"] == 32
        window.stop_notes()
        wait_for(lambda: session.status.get("VOICE_COUNT") == 0)
        result["checks"]["panic_releases_all"] = not session.active_notes
        # Keep diagnostics out of the install tree and frozen resources.
        with tempfile.TemporaryDirectory(dir=destination.parent) as directory:
            path = Path(directory) / "配置检查.json"
            tone = Tone(name="笔记本迁移检查")
            save_tone(path, tone)
            result["checks"]["configuration_roundtrip"] = load_tone(path) == tone
        result["checks"]["widgets_render"] = not window.grab().isNull()
        result["ok"] = all(result["checks"].values())
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        window.close()
        QApplication.processEvents()
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if result["ok"] else 1
