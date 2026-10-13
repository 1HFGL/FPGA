"""Validate real RTL CSV samples, then package the two timbres as preview WAVs.

These WAVs contain ModelSim RTL simulation output, not board/DAC recordings.
This tool never synthesizes substitute audio: a complete, bit-exact RTL capture
must be supplied. Python's closed-form model is only used to check that capture.
"""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import struct
import wave


SAMPLE_RATE = 48000
SAMPLES_PER_TIMBRE = 48000
PREVIEW_GAIN = 8
NOTE = 69
PHASE_INC = int(440 * (1 << 32) / SAMPLE_RATE + 0.5)


def expected_sample(index, bright):
    """Independent segment equations, old-phase DDS, floor gain and quiet mix."""
    if index < 96:
        level = 65536 * (index + 1) // 96
    elif index < 24096:
        level = 65536 - (65536 - 6554) * (index - 95) // 24000
    elif index < 36000:
        level = 6554
    elif index < 41760:
        level = 6554 - 6554 * (index - 35999) // 5760
    else:
        level = 0
    address = ((PHASE_INC * index) & 0xFFFFFFFF) >> 22
    theta = 2 * math.pi * address / 1024
    if bright:
        value = 32767 * (
            8 * math.sin(theta) + 4 * math.sin(2 * theta)
            + 2 * math.sin(3 * theta) + math.sin(4 * theta)
        ) / 15
    else:
        value = 32767 * math.sin(theta)
    raw = int(abs(value) + 0.5) * (-1 if value < 0 else 1)
    # Unity velocity = 65536, so the second gain stage leaves this value intact.
    return (raw * level // 65536) // 32


def read_and_check_capture(path):
    parts = {0: [], 1: []}
    with path.open(newline="", encoding="ascii") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != ["timbre", "note", "index", "sample"]:
            raise ValueError("RTL capture must have header timbre,note,index,sample")
        for line, row in enumerate(reader, start=2):
            if None in row or any(value is None for value in row.values()):
                raise ValueError(f"Line {line}: missing or extra CSV columns")
            try:
                timbre, note, index, sample = (int(row[name]) for name in reader.fieldnames)
            except ValueError as error:
                raise ValueError(f"Line {line}: noninteger RTL capture field") from error
            if timbre not in parts or note != NOTE:
                raise ValueError(f"Line {line}: expected timbre 0/1 and note {NOTE}")
            if index != len(parts[timbre]) or index >= SAMPLES_PER_TIMBRE:
                raise ValueError(f"Line {line}: duplicate, missing, unordered or extra sample index {index}")
            if not -32768 <= sample <= 32767:
                raise ValueError(f"Line {line}: sample outside signed 16-bit range")
            expected = expected_sample(index, bool(timbre))
            if sample != expected:
                raise ValueError(f"Line {line}, timbre {timbre}, sample {index}: actual {sample}, expected {expected}")
            parts[timbre].append(sample)
    for timbre, samples in parts.items():
        if len(samples) != SAMPLES_PER_TIMBRE:
            raise ValueError(f"Timbre {timbre}: incomplete RTL capture ({len(samples)}/48000)")
        if not (min(samples) < 0 < max(samples)) or any(samples[41760:]):
            raise ValueError(f"Timbre {timbre}: missing signed sound or completed release silence")
    return parts


def measure_harmonics(samples):
    # At 440 Hz, 9600 samples contain 88 cycles. This is after decay and before
    # release, so a fixed ADSR gain does not distort the spectrum measurement.
    stable = samples[25000:34600]
    harmonics = []
    for harmonic in range(1, 5):
        omega = 2 * math.pi * 440 * harmonic / SAMPLE_RATE
        cosine = math.fsum(sample * math.cos(omega * index) for index, sample in enumerate(stable))
        sine = math.fsum(sample * math.sin(omega * index) for index, sample in enumerate(stable))
        harmonics.append(2 * math.hypot(cosine, sine) / len(stable))
    if harmonics[0] <= 1:
        raise ValueError("Missing fundamental in the steady measurement window")
    return harmonics, [value / harmonics[0] for value in harmonics]


def write_wav(path, samples):
    amplified = [sample * PREVIEW_GAIN for sample in samples]
    if min(amplified) < -32768 or max(amplified) > 32767:
        raise ValueError(f"Preview gain would clip {path.name}; refusing to alter samples")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(struct.pack(f"<{len(amplified)}h", *amplified))


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, default=root / "build/regression/logs/timbre_preview.csv")
    parser.add_argument("--out-dir", type=Path, default=root / "build/audio")
    parser.add_argument("--report", type=Path, help="optional JSON report path; default is inside output directory")
    args = parser.parse_args()
    parts = read_and_check_capture(args.capture)
    spectra = {mode: measure_harmonics(samples) for mode, samples in parts.items()}
    if max(spectra[0][1][1:]) >= 0.01:
        raise ValueError("Soft RTL audio has unexpected strong harmonics")
    for actual, expected in zip(spectra[1][1][1:], (0.5, 0.25, 0.125)):
        if abs(actual - expected) > 0.02:
            raise ValueError(f"Bright RTL harmonic ratio {actual} differs from {expected}")
    # Only create delivered artifacts after every capture and spectrum check passes.
    args.out_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "source": "ModelSim RTL simulation CSV; not a physical board/DAC recording",
        "capture_sha256": hashlib.sha256(args.capture.read_bytes()).hexdigest(),
        "bit_exact_checked_samples": 2 * SAMPLES_PER_TIMBRE,
        "sample_rate_hz": SAMPLE_RATE,
        "note": NOTE,
        "phase_increment": PHASE_INC,
        "actual_dds_fundamental_hz": PHASE_INC * SAMPLE_RATE / (1 << 32),
        "gate_high_samples": 36000,
        "adsr_samples": {"attack": 96, "decay": 24000, "sustain_q16": 6554, "release": 5760},
        "shared_preview_gain": PREVIEW_GAIN,
        "separate_normalization": False,
        "steady_window": {"first": 25000, "stop_exclusive": 34600, "length": 9600},
        "timbres": {},
    }
    for mode, name in ((0, "soft"), (1, "bright")):
        samples = parts[mode]
        harmonics, ratios = spectra[mode]
        output = args.out_dir / f"timbre_{name}.wav"
        write_wav(output, samples)
        report["timbres"][name] = {
            "file": output.name,
            "samples": len(samples),
            "duration_seconds": len(samples) / SAMPLE_RATE,
            "raw_min": min(samples), "raw_max": max(samples),
            "preview_min": min(samples) * PREVIEW_GAIN,
            "preview_max": max(samples) * PREVIEW_GAIN,
            "steady_harmonic_amplitudes": harmonics,
            "steady_harmonic_ratios": ratios,
            "wav_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        }
        print(f"PASS {name} RTL preview: {len(samples)} exact samples, final silence, H1..H4/H1="
              + ",".join(f"{ratio:.6f}" for ratio in ratios))
    report_path = args.report or args.out_dir / "timbre_preview_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("PASS two RTL preview WAVs: mono PCM16 / 48000 Hz, common gain x8, no clipping.")
    print("Scope: actual RTL simulation output only; not board audio or a subjective listening pass.")


if __name__ == "__main__":
    main()
