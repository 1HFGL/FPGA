"""核对实际 RTL 导出的乐器 CSV，再把原始输出包装为 48 kHz 试听 WAV。

禁止用参考模型代替录得的 RTL 数据：必须提供完整、逐点匹配的 CSV。
数学公式仅用于核对，WAV 所用的每个样本均来自 CSV。这不是板上录音。
"""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import struct
import wave


FS = 48000
UNITY = 65536
KINDS = {"probe": 96000, "melody": 120000}
NAMES = {0: "guitar", 1: "strings"}
NOTES = (60, 62, 64, 67, 72)
# 独立数学合同，不导入生成器、仿真器模型或读取 ROM。
PARAMS = {0: dict(attack=64, decay=32768, sustain=0, release=4096, tone_samples=8192),
          1: dict(attack=1024, decay=8192, sustain=49152, release=8192, tone_samples=2048)}


def round_away(value):
    return int(abs(value)+0.5) * (-1 if value < 0 else 1)


def phase_increment(note):
    return int(440.0 * 2.0 ** ((note-69)/12) * 2**32 / FS + 0.5)


def make_reference_functions():
    """按公开公式预计算期望函数，不从生成器或 ROM 取常量。"""
    base, guitar, strings = [], [], []
    for address in range(1024):
        t = 2 * math.pi * address / 1024
        base.append(round_away(32767 * math.sin(t)) // 2)
        guitar.append(round_away(32767/32 * (
            16*math.sin(t) + 8*math.sin(2*t) + 4*math.sin(3*t)
            + 2*math.sin(5*t) + math.sin(6*t) + math.sin(7*t))))
        strings.append(round_away(32767/32 * (
            16*math.sin(t) + 6*math.sin(2*t) + 3*math.sin(3*t)
            + 2*math.sin(4*t) + 2*math.sin(5*t) + math.sin(6*t)
            + math.sin(7*t) + math.sin(8*t))))
    return base, {0: guitar, 1: strings}


def controls(kind, index):
    if kind == "probe":
        return 69, int(index < 72000), index, 72000
    segment, age = divmod(index, 24000)
    return NOTES[segment], int(age < 14400), age, 14400


def held_envelope(age, params):
    """分段距离*k/N 公式，与 RTL 商/余数逐拍实现相互独立。"""
    a, d, s = params["attack"], params["decay"], params["sustain"]
    if age < a:
        return UNITY * (age+1) // a
    if age < a+d:
        return UNITY - (UNITY-s) * (age-a+1) // d
    return s


def envelope(age, gate_stop, params):
    if age < gate_stop:
        return held_envelope(age, params)
    release_step = age-gate_stop+1
    if release_step >= params["release"]:
        return 0
    start_level = held_envelope(gate_stop-1, params)
    return start_level - start_level * release_step // params["release"]


def expected_sample(kind, instrument, index, base, full):
    note, _, age, gate_stop = controls(kind, index)
    inc = phase_increment(note)
    if kind == "probe":
        phase = inc * index
    else:
        segment = index // 24000
        phase = sum(phase_increment(n)*24000 for n in NOTES[:segment]) + inc*age
    address = (phase & 0xFFFFFFFF) >> 22  # ROM 读取旧相位，然后相位才推进。
    p = PARAMS[instrument]
    tone_age = min(age, p["tone_samples"])
    brightness = (65536 - 61440*tone_age//8192) if instrument == 0 else (8192+24576*tone_age//2048)
    if inc >= 0x10000000:
        brightness = 0
    shaped = base[address] + (full[instrument][address]-base[address]) * brightness // UNITY
    level = envelope(age, gate_stop, p)
    # 每声部 ADSR 缩放后向负无穷取整。127 力度为单位增益；只开一路。
    return (shaped * level // UNITY) // 32


def read_and_check(path):
    parts = {(kind, mode): [] for kind in KINDS for mode in NAMES}
    base, full = make_reference_functions()
    with path.open(newline="", encoding="ascii") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != ["kind", "instrument", "index", "note", "gate", "sample"]:
            raise ValueError("Capture header must be kind,instrument,index,note,gate,sample")
        for line, row in enumerate(reader, 2):
            if None in row or any(value is None for value in row.values()):
                raise ValueError(f"Line {line}: missing or extra CSV fields")
            kind = row["kind"]
            try:
                mode, index, note, gate, sample = (int(row[key]) for key in ("instrument", "index", "note", "gate", "sample"))
            except ValueError as error:
                raise ValueError(f"Line {line}: expected integer capture fields") from error
            key = (kind, mode)
            if key not in parts:
                raise ValueError(f"Line {line}: unknown clip {key}")
            if index != len(parts[key]) or index >= KINDS[kind]:
                raise ValueError(f"Line {line}: unordered, missing, duplicate or extra index {index} in {key}")
            expected_note, expected_gate, _, _ = controls(kind, index)
            if (note, gate) != (expected_note, expected_gate):
                raise ValueError(f"Line {line}: wrong note/gate {(note,gate)}, expected {(expected_note,expected_gate)}")
            if not -32768 <= sample <= 32767:
                raise ValueError(f"Line {line}: signed 16-bit sample overflow")
            expected = expected_sample(kind, mode, index, base, full)
            if sample != expected:
                raise ValueError(f"Line {line}, {kind}/{NAMES[mode]}[{index}]: actual {sample}, expected {expected}")
            parts[key].append(sample)
    for (kind, mode), samples in parts.items():
        if len(samples) != KINDS[kind]:
            raise ValueError(f"{kind}/{NAMES[mode]} incomplete: {len(samples)}/{KINDS[kind]}")
        if not min(samples) < 0 < max(samples):
            raise ValueError(f"{kind}/{NAMES[mode]}: missing signed audible signal")
        for end in ([96000] if kind == "probe" else [24000, 48000, 72000, 96000, 120000]):
            if any(samples[end-1000:end]):
                raise ValueError(f"{kind}/{NAMES[mode]}: completed release is not silent before index {end}")
        print(f"PASS {kind}/{NAMES[mode]}: {len(samples)} bit-exact RTL samples, request metadata, completed release silence.")
    return parts


def statistics(samples):
    return dict(minimum=min(samples), maximum=max(samples),
                peak=max(abs(min(samples)), abs(max(samples))),
                rms=math.sqrt(math.fsum(value*value for value in samples)/len(samples)),
                mean=math.fsum(samples)/len(samples))


def spectrum(samples, first, stop):
    """Hann 窗抑制非整数周期的泄漏；包络/亮度变化仍会调制频谱。"""
    data = samples[first:stop]
    weights = [0.5-0.5*math.cos(2*math.pi*i/(len(data)-1)) for i in range(len(data))]
    weight_sum = math.fsum(weights)
    average = math.fsum(value*w for value, w in zip(data, weights))/weight_sum
    windowed = [(value-average)*w for value, w in zip(data, weights)]
    actual_hz = phase_increment(69)*FS/2**32
    levels = []
    for h in range(1, 9):
        omega = 2*math.pi*actual_hz*h/FS
        cosine = math.fsum(value*math.cos(omega*i) for i, value in enumerate(windowed))
        sine = math.fsum(value*math.sin(omega*i) for i, value in enumerate(windowed))
        levels.append(2*math.hypot(cosine, sine)/weight_sum)
    if levels[0] <= 1:
        raise ValueError("Missing fundamental in harmonic measurement window")
    return dict(first=first, stop_exclusive=stop, window="Hann, weighted mean removed",
                harmonic_amplitudes=levels, harmonic_ratios=[v/levels[0] for v in levels],
                raw_rms=statistics(data)["rms"])


def check_spectral_trends(parts):
    windows = dict(early=(256,1536), late=(20000,29600), held=(50000,59600))
    result = {}
    for mode, name in NAMES.items():
        result[name] = {label: spectrum(parts[("probe",mode)], *bounds)
                        for label,bounds in windows.items() if mode == 1 or label != "held"}
    g_early = result["guitar"]["early"]["harmonic_ratios"][1]
    g_late = result["guitar"]["late"]["harmonic_ratios"][1]
    if not g_early > 4*g_late or not 0.02 < g_late < 0.045:
        raise ValueError(f"Guitar brightness trend mismatch: early H2/H1={g_early}, late={g_late}")
    s_late = result["strings"]["late"]["harmonic_ratios"]
    s_held = result["strings"]["held"]["harmonic_ratios"]
    if abs(s_late[1]-0.1875) > 0.02 or max(abs(a-b) for a,b in zip(s_late,s_held)) > 0.01:
        raise ValueError("Strings steady harmonic mixture changed during sustain")
    rms_ratio = result["strings"]["held"]["raw_rms"] / result["strings"]["late"]["raw_rms"]
    if not 0.98 < rms_ratio < 1.02:
        raise ValueError(f"Strings sustain unexpectedly fades: late-to-held RMS ratio={rms_ratio}")
    print(f"PASS guitar brightness: Hann-window H2/H1 {g_early:.6f} early -> {g_late:.6f} late.")
    print(f"PASS strings sustain: H2/H1={s_late[1]:.6f}, held/late RMS={rms_ratio:.6f}.")
    return result


def choose_gains(parts, target_rms, peak_limit):
    melody_rms = {m: statistics(parts[("melody",m)])["rms"] for m in NAMES}
    global_peaks = {m: max(statistics(parts[(k,m)])["peak"] for k in KINDS) for m in NAMES}
    # 同时限制两种片段的峰值；必要时共同降低目标 RMS，而不是单独削顶。
    matched_target = min(target_rms, *(melody_rms[m]*peak_limit/global_peaks[m] for m in NAMES))
    gains = {m: matched_target/melody_rms[m] for m in NAMES}
    return matched_target, gains


def write_wav(path, samples):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(FS)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, default=root/"results/logs/instrument_preview.csv")
    parser.add_argument("--out-dir", type=Path, default=root/"results/audio")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--target-rms", type=float, default=2000)
    parser.add_argument("--peak-limit", type=int, default=28000)
    parser.add_argument("--validate-only", action="store_true", help="check capture without writing WAV/report")
    args = parser.parse_args()
    if not math.isfinite(args.target_rms) or args.target_rms <= 0 or not 1 <= args.peak_limit <= 32767:
        raise ValueError("Expected positive finite target RMS and peak limit in 1..32767")
    parts = read_and_check(args.capture)
    spectra = check_spectral_trends(parts)
    matched_target, gains = choose_gains(parts,args.target_rms,args.peak_limit)
    preview = {key: [round_away(sample*gains[key[1]]) for sample in samples] for key,samples in parts.items()}
    if any(statistics(samples)["peak"] > args.peak_limit for samples in preview.values()):
        raise ValueError("Normalized preview exceeds peak limit; refusing clipping")
    normalized_rms = [statistics(preview[("melody",m)])["rms"] for m in NAMES]
    if max(normalized_rms)-min(normalized_rms) > 1.0:
        raise ValueError("Melody previews are not matched within 1 PCM16 RMS unit")
    print(f"PASS preview normalization: common melody RMS target {matched_target:.6f}; "
          f"guitar gain x{gains[0]:.6f}, strings gain x{gains[1]:.6f}; peak <= {args.peak_limit}.")
    if args.validate_only:
        print("PASS instrument capture validation only: no artifacts written.")
        return
    # 所有正确性检查完成后才导出实际录得的 RTL 样本。
    args.out_dir.mkdir(parents=True,exist_ok=True)
    report = dict(source="Actual RTL simulation CSV; not a physical board or DAC recording",
                  capture_sha256=hashlib.sha256(args.capture.read_bytes()).hexdigest(),
                  bit_exact_checked_samples=sum(len(x) for x in parts.values()), sample_rate_hz=FS,
                  probe_note=69, melody_notes=list(NOTES), params=PARAMS,
                  requested_melody_rms=args.target_rms, achieved_target_melody_rms=matched_target,
                  preview_peak_limit=args.peak_limit, preview_gain_policy="one fixed playback gain per preset, shared across probe/melody; not FPGA logic",
                  spectral_scope="Hann-window measurements of actual RTL output; early windows have ADSR and brightness modulation; ratios demonstrate trends, not stationary ROM spectra or subjective realism",
                  spectra=spectra, clips={})
    for (kind,mode), actual in parts.items():
        name = NAMES[mode]
        path = args.out_dir / f"instrument_{name}_{kind}.wav"
        played = preview[(kind,mode)]
        write_wav(path,played)
        report["clips"][f"{kind}/{name}"] = dict(file=path.name,samples=len(actual),
                duration_seconds=len(actual)/FS,raw=statistics(actual),preview=statistics(played),
                playback_gain=gains[mode],wav_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    report_path = args.report or args.out_dir/"instrument_preview_report.json"
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print("PASS instrument preview WAVs: 432000 exact RTL samples; mono PCM16 / 48000 Hz; no clipping.")
    print("Scope: mathematical and simulated audio evidence only; hardware and subjective listening remain separate checks.")


if __name__ == "__main__":
    main()
