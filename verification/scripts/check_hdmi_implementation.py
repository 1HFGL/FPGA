"""检查HDMI构建身份、引脚覆盖及五类最差路径；不代替板级电气/实物签核。"""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument("--directory", type=Path, default=Path("build/hdmi"))
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.directory.resolve()
errors = []

def check(condition, message):
    if not condition:
        errors.append(message)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

manifest = (out / "build_inputs.txt").read_text(encoding="utf-8-sig")
inputs = []
for line in manifest.splitlines():
    match = re.fullmatch(r"([A-Fa-f0-9]{64})  (.+)", line)
    if match:
        path = Path(match[2])
        check(path.is_file() and digest(path) == match[1].lower(), f"Input changed: {path}")
        inputs.append({"path": str(path), "sha256": match[1].lower()})
check(len(inputs) >= 40, "Incomplete build manifest")
log = (out / "build.log").read_text(encoding="utf-8-sig")
check(not re.search(r"ERROR|EX3988|EX3791|EX3073|TA2003", log), "Unresolved build warning/error")
check("Bitstream generation completed" in log, "Bitstream generation missing")
timing = (out / "timing.txt").read_text(encoding="utf-8-sig")
slacks = {}
for section in ("3.1.1 Setup Paths Table", "3.1.2 Hold Paths Table",
                "3.1.3 Recovery Paths Table", "3.1.4 Removal Paths Table", "3.2 Minimum Pulse Width Table"):
    table = timing.split(section, 1)[1].strip().split("\n\n", 1)[0] if section in timing else ""
    values = [float(x) for x in re.findall(r"(?m)^\s*\d+\s+(-?\d+\.\d+)\s+", table)]
    check(bool(values), f"Missing timing rows: {section}")
    if values:
        slacks[section] = min(values)
        check(min(values) >= 0, f"Negative slack {min(values)}ns: {section}")
for clock in ("sys_clk", "hdmi_pixel", "hdmi_serial"):
    for kind in ("Setup", "Hold"):
        check(re.search(rf"(?m)^{clock} {kind} 0\.000 0$", timing), f"Clock summary failed: {clock} {kind}")
active_constraints = len(re.findall(r"(?m)^TC_\w+ Actived ", timing))
check(active_constraints == 21, f"Expected 21 active constraints (17 existing + 4 BLE), got {active_constraints}")
report = (out / "piano_hdmi.rpt.txt").read_text(encoding="utf-8-sig")
ports = {}
for line in report.splitlines():
    cells = [x.strip() for x in line.split("|")]
    if len(cells) > 5 and re.fullmatch(r"\w+(?:\[\d+\])?", cells[0]) and re.fullmatch(r"[A-Z]+\d+/\d+", cells[2]):
        ports[cells[0]] = (cells[2].split("/")[0], cells[3])
check(len(ports) == 37, f"Expected 37 pin-constrained ports (34 existing + 3 BLE), got {len(ports)}")
expected_pins = {}
for name in ("piano", "hdmi", "ble"):
    cst = (root / f"boards/tang_mega_60k_31004/{name}.cst").read_text(encoding="utf-8-sig")
    expected_pins.update(re.findall(r'IO_LOC\s+"([^"]+)"\s+([A-Z]+\d+)', cst))
expected_pins.update({"tmds_data_n[0]": "H14", "tmds_data_n[1]": "H15", "tmds_data_n[2]": "J17", "tmds_clk_n": "G16"})
check(len(expected_pins) == 37, "CST/negative pair coverage mismatch")
for name, pin in expected_pins.items():
    check(ports.get(name) == (pin, "Y"), f"Pin missing/moved/unconstrained: {name}")
resources = {}
for name in ("Logic", "Register", "BSRAM", "DSP", "PLLA"):
    # Gowin DSP可按半块计数（例如13.5），不能把合法报告误判为缺失。
    match = re.search(rf"(?m)^\s*{name}\s*\|\s*(\d+(?:\.\d+)?)/(\d+)", report)
    check(match is not None, f"Missing resource: {name}")
    if match:
        used=float(match[1])
        resources[name] = {"used": int(used) if used.is_integer() else used, "available": int(match[2])}
# INS_LOC匹配到网表并不保证真的改善时序；同时核对12个原语实际落点。
# 只读本次工具生成的详细STA，不从手写约束反推“已经布局成功”。
placement_source = root / "boards/tang_mega_60k_31004/hdmi_reset_placement.cst"
expected_placement = dict(re.findall(r'INS_LOC\s+"([^"]+)"\s+(R\d+C\d+);',
                                    placement_source.read_text(encoding="utf-8-sig")))
check(len(expected_placement) == 12, "Expected twelve local reset placement constraints")
detail_html = out / "piano_hdmi_tr_content.html"
if detail_html.exists():
    detail = html.unescape(re.sub(r"<[^>]*>", " ", detail_html.read_text(encoding="utf-8-sig")))
else:
    detail = (out / "piano_hdmi.tr").read_text(encoding="utf-8-sig")
actual_placement = {}
for location, node in re.findall(r'(R\d+C\d+\[\d+\]\[[AB]\])\s+(\S+)', detail):
    instance = node.rsplit("/", 1)[0]
    if instance in expected_placement:
        actual_placement.setdefault(instance, set()).add(location)
for instance, grid in expected_placement.items():
    locations = actual_placement.get(instance, set())
    check(bool(locations) and all(location.split("[")[0] == grid for location in locations),
          f"Reset placement missing/moved: {instance} -> {sorted(locations)}, expected {grid}")
for section in ("3.1.3 Recovery Paths Table", "3.1.4 Removal Paths Table"):
    check(slacks.get(section, -1) >= 0.100, f"Reset optimization margin below 0.100ns: {section}")
base = root / "projects/hdmi"
check(digest(base / "process_config.json") == digest(base / "impl/piano_hdmi_process_config.json"), "Process options changed")
fs = base / "impl/pnr/piano_hdmi.fs"
artifact = (out / "artifact.txt").read_text(encoding="utf-8-sig")
recorded_hash = re.search(r"(?im)^sha256=([a-f0-9]{64})$", artifact)
check(recorded_hash is not None and recorded_hash[1].lower() == digest(fs), "Bitstream identity mismatch")
summary = {"status": "FAIL" if errors else "PASS_CURRENT_CONSTRAINTS_ONLY", "errors": errors,
           "worst_reported_slack_ns": slacks, "ports": len(ports), "active_constraints": active_constraints,
           "resources": resources, "bitstream_sha256": digest(fs), "inputs": inputs,
           "reset_placement": {name: sorted(locations) for name, locations in actual_placement.items()},
           "limitations": ["PR1014 system clock generic routing remains", "DAC external timing incomplete",
                           "HDMI electrical eye/cable/receiver not measured", "USB touch not implemented",
                           "Not programmed; screen compatibility and end-to-end latency unverified"]}
(out / "implementation_check.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
if errors:
    raise SystemExit("FAIL HDMI implementation: " + "; ".join(errors))
print("PASS HDMI current constraints: 37 pins, 21 constraints, five timing tables, input/bitstream identity")
