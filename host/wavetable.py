"""Waveform generation and FPGA table export helpers."""
from pathlib import Path
import numpy as np


WAVEFORMS = ["Sine", "Triangle", "Saw", "Square", "Additive"]


def generate_waveform(kind, length=256, harmonics=8, amplitude=1.0):
    length = max(16, int(length))
    phase = np.linspace(0.0, 2.0 * np.pi, length, endpoint=False)
    kind = kind.lower()

    if kind == "sine":
        wave = np.sin(phase)
    elif kind == "triangle":
        wave = 2.0 / np.pi * np.arcsin(np.sin(phase))
    elif kind == "saw":
        wave = 2.0 * (phase / (2.0 * np.pi)) - 1.0
    elif kind == "square":
        wave = np.where(np.sin(phase) >= 0.0, 1.0, -1.0)
    elif kind == "additive":
        wave = np.zeros_like(phase)
        for h in range(1, max(1, int(harmonics)) + 1):
            wave += np.sin(h * phase) / h
        peak = np.max(np.abs(wave))
        if peak > 0:
            wave = wave / peak
    else:
        raise ValueError(f"Unsupported waveform: {kind}")

    wave = np.asarray(wave, dtype=np.float64)
    wave = np.clip(wave * float(amplitude), -1.0, 1.0)
    return wave


def signed16(wave):
    values = np.rint(np.asarray(wave, dtype=np.float64) * 32767.0)
    return np.clip(values, -32768, 32767).astype(np.int16)


def export_csv(path, wave):
    data = np.column_stack((np.arange(len(wave)), wave, signed16(wave)))
    np.savetxt(path, data, delimiter=",", header="index,float,signed16", comments="", fmt=["%d", "%.9f", "%d"])


def export_hex(path, wave, samples_per_line=16):
    values = signed16(wave)
    lines = []
    for start in range(0, len(values), samples_per_line):
        chunk = values[start:start + samples_per_line]
        lines.append(" ".join(f"{(int(v) & 0xFFFF):04X}" for v in chunk))
    Path(path).write_text("\n".join(lines) + "\n", encoding="ascii")


def export_mif(path, wave, depth=None, width=16):
    values = signed16(wave)
    if depth is None:
        depth = len(values)
    lines = [
        f"DEPTH = {int(depth)};",
        f"WIDTH = {int(width)};",
        "ADDRESS_RADIX = DEC;",
        "DATA_RADIX = HEX;",
        "CONTENT",
        "BEGIN",
    ]
    for index, value in enumerate(values):
        lines.append(f"  {index:5d} : {(int(value) & 0xFFFF):04X};")
    lines.append("END;")
    Path(path).write_text("\n".join(lines) + "\n", encoding="ascii")