"""Collect reproducible integration evidence; fail if results or inputs are stale."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "8277946b67fabd4ed03ae606d7b62632df6c6080"
OUT = ROOT / "verification/evidence/performance"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_log(relative, marker):
    body = (ROOT / relative).read_text(encoding="utf-8-sig", errors="replace")
    if marker not in body or re.search(r"\bFAIL\b|\*\* (?:Fatal|Error):", body):
        raise RuntimeError(f"Missing pass or failure in {relative}")
    return body


def check_manifest(relative):
    entries = {}
    for line in (ROOT / relative).read_text(encoding="utf-8-sig").splitlines():
        match = re.match(r"([A-Fa-f0-9]{64})  (.+)$", line)
        if match:
            path = Path(match[2])
            if not path.is_absolute():
                path = ROOT / path
            actual = digest(path)
            if actual != match[1].lower():
                raise RuntimeError(f"Stale input: {path}")
            entries[path.relative_to(ROOT).as_posix()] = actual
    if not entries:
        raise RuntimeError(f"Empty manifest: {relative}")
    return entries


tests = ["bank", "system", "adc", "control", "latency"]
normal_logs = {}
for test in tests:
    relative = f"build/regression/performance/None/tb_performance_{test}.log"
    normal_logs[test] = checked_log(relative, f"PASS tb_performance_{test}:")
mutations = {}
for mode, test, failure in [("Volume", "system", "master gain not connected"),
                            ("Bend", "adc", "ADC did not bend")]:
    relative = f"build/regression/performance/{mode}/tb_performance_{test}.log"
    body = (ROOT / relative).read_text(encoding="utf-8-sig")
    if f"FAIL: {failure}" not in body or "** Error:" in body:
        raise RuntimeError(f"Wrong mutation failure: {mode}")
    mutations[mode] = {"test": test, "rejected_by": failure}

sources = check_manifest("build/regression/strict/strict_inputs.txt")
build_sources = check_manifest("build/performance/build_inputs.txt")
timing = (ROOT / "build/performance/timing_from_html.txt").read_text(encoding="utf-8-sig")
slack = {}
for title in ["Setup", "Hold", "Recovery", "Removal"]:
    section = timing.split(f"{title} Paths Table\n", 1)[1].split("\n\n", 1)[0]
    values = [float(x) for x in re.findall(r"(?m)^\d+ (-?\d+\.\d+) ", section)]
    if not values or min(values) < 0:
        raise RuntimeError(f"Timing failure: {title}")
    slack[title.lower()] = min(values)
report = (ROOT / "build/performance/piano_performance.rpt.txt").read_text(encoding="utf-8-sig")
resources = {}
for name in ["Logic", "Register", "BSRAM", "DSP"]:
    match = re.search(rf"(?m)^\s*{name}\s*\|\s*([\d.]+)/([\d.]+)", report)
    if not match:
        raise RuntimeError(f"Missing resource: {name}")
    resources[name] = {"used": float(match[1]), "available": float(match[2])}
bitstream = ROOT / "projects/piano/impl/pnr/piano_performance.fs"
artifact = (ROOT / "build/performance/artifact.txt").read_text(encoding="utf-8-sig")
if digest(bitstream).upper() not in artifact:
    raise RuntimeError("Bitstream artifact mismatch")
if digest(ROOT / "projects/piano/process_config.json") != digest(ROOT / "projects/piano/impl/uart_piano_process_config.json"):
    raise RuntimeError("Effective configuration mismatch")

# Only paths that existed before this integration count as unchanged team files.
listing = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", BASELINE,
                                   "verification/tb", "upstream/fpga_interaction"], cwd=ROOT, text=True)
protected = listing.splitlines()
subprocess.run(["git", "diff", "--exit-code", BASELINE, "--", *protected], cwd=ROOT, check=True,
               stdout=subprocess.DEVNULL)
protected_hashes = {p: digest(ROOT / p) for p in protected}

observations = [int(x) for x in re.findall(r"digital_contact_to_left_DAC_word_ns=(\d+)", normal_logs["latency"])]
summary = {
    "baseline": BASELINE,
    "top": "piano_performance_top", "device": "GW5AT-LV60PG484AC1/I0/B",
    "clock_hz": 50000000, "sample_rate_hz": 48000, "voices": 16,
    "tool": {"simulator": "ModelSim SE-64 10.6e", "implementation": "Gowin V1.9.12.04"},
    "main_tests": {"all": 27, "uart": 7, "piano": 2, "keyboard": 2, "pa": 4,
                   "display": 6, "new_performance": 5, "host_python": 32},
    "strict_verilog_sources": len(sources),
    "new_test_markers": {test: re.search(r"PASS tb_performance_.*", body)[0]
                         for test, body in normal_logs.items()},
    "negative_audio_controls": mutations,
    "digital_onset": {"cases": len(observations), "maximum_observed_ns": max(observations),
                      "physical_or_worst_case_proof": False,
                      "excluded": ["contact bounce", "analog DAC/amplifier", "touch", "knob acquisition response"]},
    "resources": resources, "worst_reported_slack_ns": slack,
    "bitstream": {"path": bitstream.relative_to(ROOT).as_posix(), "sha256": digest(bitstream), "programmed": False},
    "limitations": ["PR1014 clock routing warning", "complete DAC external timing unresolved",
                    "ADC default acquisition/filter/slew response not measured; may be hundreds of milliseconds",
                    "sustain/octave internal interfaces only; board fixed off/middle", "touch/display not integrated",
                    "current piano timbre approximation unchanged"],
    "strict_source_sha256": sources, "build_input_sha256": build_sources,
    "unchanged_team_files": {"count": len(protected), "working_file_sha256": protected_hashes},
}
# These additional suites must have completed, rather than inheriting old results.
for relative, marker in [
    ("build/regression/all_current_console.log", "PASS: suite All (27 testbenches)."),
    ("build/regression/uart_current_console.log", "VERIFIED tb_uart_instrument_115200"),
    ("build/regression/piano_current_console.log", "VERIFIED tb_uart_piano_board"),
    ("build/regression/host_current_console.log", "Ran 32 tests"),
]:
    checked_log(relative, marker)
OUT.mkdir(parents=True, exist_ok=True)
for test in tests:
    shutil.copyfile(ROOT / f"build/regression/performance/None/tb_performance_{test}.log",
                    OUT / f"tb_performance_{test}.log")
for mode, test in [("Volume", "system"), ("Bend", "adc")]:
    shutil.copyfile(ROOT / f"build/regression/performance/{mode}/tb_performance_{test}.log",
                    OUT / f"negative_{mode.lower()}.log")
shutil.copyfile(ROOT / "build/performance/timing_from_html.txt", OUT / "timing_tables.txt")
shutil.copyfile(ROOT / "build/performance/piano_performance.rpt.txt", OUT / "resources.rpt.txt")
(OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(f"PASS evidence: {len(sources)} strict files; 5 new tests; protected {len(protected)} files unchanged")
