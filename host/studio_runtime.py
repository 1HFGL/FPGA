"""Identity/resources shared by source and frozen distributions."""
import json
from pathlib import Path

VERSION = "1.0.0"
PRODUCT_NAME = "声场上位机"


def resource_path(name):
    return Path(__file__).resolve().parent / name


def release_info():
    path = resource_path("release.json")
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"version": VERSION, "distribution": "source"}


def fit_to_screen(window):
    """Respect the laptop's available logical area, including high DPI."""
    screen = window.screen()
    if screen is None:
        return
    area = screen.availableGeometry()
    width = max(1, min(1280, area.width() - 24))
    height = max(1, min(860, area.height() - 48))
    window.setMinimumSize(min(1040, width), min(720, height))
    window.resize(width, height)
