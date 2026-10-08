"""Validated tone documents and the proposed SYNTH/1 control protocol.

This is a PC editor/reference model. It does not replace FPGA audio generation.
"""
from dataclasses import asdict, dataclass, field
import json
import math
import os
from pathlib import Path
import tempfile


PARAMETERS = {
    "attack_ms": (0, 10000, 5), "decay_ms": (0, 10000, 300),
    "sustain": (0, 255, 192), "release_ms": (0, 10000, 180),
    "volume": (0, 255, 64), "mode": (0, 2, 0),
    "vibrato_cents": (0, 100, 0), "vibrato_tenths_hz": (1, 120, 50),
}


def bounded_int(value, low, high, label):
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"{label} 必须是 {low}～{high} 的整数")
    return value


@dataclass
class Tone:
    name: str = "新音色"
    harmonics: list = field(default_factory=lambda: [255] + [0] * 15)
    attack_ms: int = 5
    decay_ms: int = 300
    sustain: int = 192
    release_ms: int = 180
    volume: int = 64
    mode: int = 0
    vibrato_cents: int = 0
    vibrato_tenths_hz: int = 50

    def validate(self):
        if not isinstance(self.name, str) or not self.name.strip() or len(self.name) > 80:
            raise ValueError("音色名称须为 1～80 个字符")
        if not isinstance(self.harmonics, list) or len(self.harmonics) != 16:
            raise ValueError("需要恰好 16 个谐波幅度")
        for n, value in enumerate(self.harmonics, 1):
            bounded_int(value, 0, 255, f"第 {n} 分量")
        for key, (low, high, _) in PARAMETERS.items():
            bounded_int(getattr(self, key), low, high, key)
        return self

    def copy(self):
        return Tone(**asdict(self))

    def fingerprint(self):
        """Device state excludes the PC-only display name."""
        data = asdict(self)
        data.pop("name")
        return json.dumps(data, sort_keys=True, separators=(",", ":"))

    def document(self):
        self.validate()
        return {"format": "fpga-tone-studio", "version": 1, "tone": asdict(self)}

    @classmethod
    def from_document(cls, data):
        if not isinstance(data, dict) or data.get("format") != "fpga-tone-studio":
            raise ValueError("这不是音色设计台配置；旧控制台的参数格式不能直接载入")
        if type(data.get("version")) is not int or data["version"] != 1:
            raise ValueError("不支持的配置版本")
        values = data.get("tone")
        expected = set(asdict(cls()))
        if not isinstance(values, dict) or set(values) != expected:
            raise ValueError("配置字段缺失或包含未知字段")
        return cls(**values).validate()


def load_tone(path):
    path = Path(path)
    if path.stat().st_size > 65536:
        raise ValueError("配置文件过大（最多 64 KiB）")
    return Tone.from_document(json.loads(path.read_text(encoding="utf-8-sig")))


def atomic_text(path, text, encoding="utf-8"):
    """Only replace the selected file after all bytes have been written."""
    path = Path(path)
    temp = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding=encoding,
                                         dir=path.parent, delete=False) as stream:
            temp = Path(stream.name)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp is not None and temp.exists():
            temp.unlink()


def save_tone(path, tone):
    atomic_text(path, json.dumps(tone.document(), ensure_ascii=False, indent=2) + "\n")


def cycle_samples(tone, length=1024):
    """One cycle: sum(a[h]*sin(2*pi*h*n/N)), peak-normalized to [-1,1].

    All phases start at zero. No repeated endpoint, ADSR or recording is stored.
    """
    tone.validate()
    bounded_int(length, 64, 4096, "波表长度")
    samples = [sum(a * math.sin(2 * math.pi * h * n / length)
                   for h, a in enumerate(tone.harmonics, 1)) for n in range(length)]
    peak = max(abs(x) for x in samples)
    return [x / peak for x in samples] if peak > 1e-12 else [0.0] * length


def export_hex(path, tone):
    # Round ties to even; the negative range is deliberately symmetric at -32767.
    values = [round(x * 32767) for x in cycle_samples(tone)]
    atomic_text(path, "".join(f"{v & 0xffff:04X}\n" for v in values), "ascii")


def crc16(text):
    """CRC-16/CCITT-FALSE: init FFFF, poly 1021, no reflection/xor-out."""
    crc = 0xffff
    for value in text.encode("ascii"):
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ (0x1021 if crc & 0x8000 else 0)) & 0xffff
    return crc


def apply_command(sequence, tone):
    bounded_int(sequence, 1, 2147483647, "请求编号")
    tone.validate()
    amplitudes = ",".join(str(a) for a in tone.harmonics)
    params = " ".join(str(getattr(tone, key)) for key in PARAMETERS)
    body = f"APPLY {sequence} {amplitudes} {params}"
    return f"{body} {crc16(body):04X}"


def decode_apply(line):
    """The simulator validates exactly the same wire contract as real firmware."""
    body, checksum = line.rsplit(" ", 1)
    if len(checksum) != 4 or int(checksum, 16) != crc16(body):
        raise ValueError("CRC 校验失败")
    fields = body.split(" ")
    if len(fields) != 3 + len(PARAMETERS) or fields[0] != "APPLY":
        raise ValueError("APPLY 字段数量错误")
    sequence = bounded_int(int(fields[1]), 1, 2147483647, "请求编号")
    amplitudes = [int(v) for v in fields[2].split(",")]
    params = dict(zip(PARAMETERS, map(int, fields[3:])))
    return sequence, Tone(harmonics=amplitudes, **params).validate()


def harmonic_preset(kind):
    if kind == "sine":
        return [255] + [0] * 15
    if kind == "square":
        return [round(255 / h) if h % 2 else 0 for h in range(1, 17)]
    if kind == "saw":
        return [round(255 / h) for h in range(1, 17)]
    if kind == "soft":
        return [255, 24, 40, 0, 12] + [0] * 11
    if kind == "bright":
        return [255, 128, 85, 64, 51, 43, 36, 32] + [0] * 8
    if kind == "zero":
        return [0] * 16
    raise ValueError("未知预设")
