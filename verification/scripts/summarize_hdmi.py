"""汇总当前HDMI构建与显示回归；拒绝源码已变化的历史日志，不替代硬件验收。"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from check_j13_wiring import validate_cst

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return path.read_text(encoding="utf-8-sig")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_manifest(path):
    count = 0
    for line in read(path).splitlines():
        match = re.fullmatch(r"([a-fA-F0-9]{64})  (.+)", line)
        if match:
            source = Path(match[2])
            if not source.is_absolute():
                source = ROOT / source
            if not source.is_file() or sha(source) != match[1].lower():
                raise SystemExit(f"Stale evidence: {source}")
            count += 1
    if count == 0:
        raise SystemExit(f"Empty input manifest: {path}")
    return count


def checked_test(path, test, expected=None):
    body = read(path)
    marker = re.search(r"(?m)^# PASS[^\r\n]*", body)
    if not marker or re.search(r"\bFAIL\b|\*\* (Error|Fatal):", body) or (expected and expected not in body):
        raise SystemExit(f"Missing passing self-check: {test}")
    return {"test": test, "marker": marker[0], "log_sha256": sha(path)}


def no_screen_result():
    directory = ROOT / "build/performance"
    verify_manifest(directory / "build_inputs.txt")
    bitstream = ROOT / "projects/piano/impl/pnr/piano_performance.fs"
    if sha(bitstream).upper() not in read(directory / "artifact.txt"):
        raise SystemExit("No-screen bitstream identity mismatch")
    if sha(ROOT / "projects/piano/process_config.json") != sha(ROOT / "projects/piano/impl/uart_piano_process_config.json"):
        raise SystemExit("No-screen process options mismatch")
    log = read(directory / "build.log")
    if "Bitstream generation completed" not in log or re.search(r"ERROR|EX3988|EX3791|EX3073|TA2003", log):
        raise SystemExit("No-screen build did not pass")
    timing = read(directory / "timing_from_html.txt")
    slacks = {}
    for name in ("3.1.1 Setup Paths Table", "3.1.2 Hold Paths Table", "3.1.3 Recovery Paths Table", "3.1.4 Removal Paths Table", "3.2 Minimum Pulse Width Table"):
        table = timing.split(name, 1)[1].strip().split("\n\n", 1)[0]
        values = [float(x) for x in re.findall(r"(?m)^\d+ (-?\d+\.\d+) ", table)]
        if not values or min(values) < 0:
            raise SystemExit(f"No-screen timing failed: {name}")
        slacks[name] = min(values)
    if len(re.findall(r"(?m)^TC_\w+ Actived ", timing)) != 10:
        raise SystemExit("No-screen active constraint mismatch")
    report = read(directory / "piano_performance.rpt.txt")
    resources = {}
    for name in ("Logic", "Register", "BSRAM", "DSP"):
        match = re.search(rf"(?m)^\s*{name}\s*\|\s*(\d+)/(\d+)", report)
        if not match:
            raise SystemExit(f"No-screen resource missing: {name}")
        resources[name] = {"used": int(match[1]), "available": int(match[2])}
    return {"status": "PASS_CURRENT_CONSTRAINTS_ONLY", "resources": resources,
            "worst_reported_slack_ns": slacks, "bitstream_sha256": sha(bitstream),
            "build_manifest_sha256": sha(directory / "build_inputs.txt"), "hardware_programmed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record-failed-implementation", action="store_true",
                        help="记录当前失败的实现供诊断；仍返回非零，不作为发布通过")
    args = parser.parse_args()
    output = ROOT / "verification/evidence/hdmi/summary.json"
    old = json.loads(read(output)) if output.exists() else {}
    implementation = json.loads(read(ROOT / "build/hdmi/implementation_check.json"))
    implementation_passed = implementation["status"] == "PASS_CURRENT_CONSTRAINTS_ONLY"
    if not implementation_passed and not args.record_failed_implementation:
        raise SystemExit("HDMI implementation not accepted")
    verify_manifest(ROOT / "build/hdmi/build_inputs.txt")
    artifact = ROOT / "projects/hdmi/impl/pnr/piano_hdmi.fs"
    if sha(artifact) != implementation["bitstream_sha256"]:
        raise SystemExit("Bitstream identity mismatch")
    for item in implementation["inputs"]:
        if sha(Path(item["path"])) != item["sha256"]:
            raise SystemExit(f"Stale implementation checker inputs: {item['path']}")
        item["path"] = Path(item["path"]).relative_to(ROOT).as_posix()
    suites = {
        "display": ["tb_display_timing", "tb_display_cdc", "tb_display_wave", "tb_display_renderer", "tb_display_reset_gain", "tb_instrument_display"],
        "hdmi": ["tb_tmds_encoder", "tb_hdmi_phy", "tb_display_hdmi_frame", "tb_hdmi_audio_isolation"],
        "hdmi_reset": ["tb_review_hdmi_reset_recovery"],
        "review": ["tb_review_arithmetic", "tb_review_font", "tb_review_layout"],
        "uart": ["tb_uart_bytes", "tb_uart_line", "tb_uart_protocol", "tb_uart_flow", "tb_uart_replies", "tb_uart_instrument", "tb_uart_instrument_115200"],
        "capacity": ["tb_review_uart_capacity", "tb_review_uart_capacity_top"],
        "dual": ["tb_review_dual_math", "tb_review_dual_voice", "tb_review_dual_system"],
    }
    evidence = []
    for suite, tests in suites.items():
        directory = ROOT / f"build/regression/{suite}"
        verify_manifest(directory / "normal_inputs.txt")
        for test in tests:
            path = directory / f"{test}_normal.log"
            evidence.append(checked_test(path, test, f"PASS {test}"))
    # 旧测试保持原样；使用其运行脚本中的完整PASS判据，不能只搜一个PASS字样。
    all_dir = ROOT / "build/regression/logs"
    verify_manifest(all_dir / "All_sha256.txt")
    marker_table = read(ROOT / "verification/scripts/run_tests.ps1").split("$markers = @{", 1)[1].split("\n}", 1)[0]
    all_markers = re.findall(r"(?m)^\s*(\w+) = '([^']+)'", marker_table)
    if len(all_markers) != 27:
        raise SystemExit("Review changed All-suite test inventory")
    for test, marker in all_markers:
        evidence.append(checked_test(all_dir / f"{test}.log", test, marker))
    performance_tests = [f"tb_performance_{x}" for x in ("bank", "system", "adc", "control", "latency")]
    performance_dir = ROOT / "build/regression/performance/None"
    verify_manifest(performance_dir / "inputs.txt")
    for test in performance_tests:
        evidence.append(checked_test(performance_dir / f"{test}.log", test, f"PASS {test}:"))
    audio_mutations = []
    for mutation, test, expected in (("Volume", "tb_performance_system", "FAIL: master gain not connected"),
                                     ("Bend", "tb_performance_adc", "FAIL: ADC did not bend")):
        directory = ROOT / f"build/regression/performance/{mutation}"
        verify_manifest(directory / "inputs.txt")
        body = read(directory / f"{test}.log")
        if expected not in body or f"PASS {test}:" in body:
            raise SystemExit(f"Audio mutation not rejected: {mutation}")
        audio_mutations.append({"mutation": mutation, "test": test, "rejected": True})
    knob_dir = ROOT / "build/regression/knob"
    verify_manifest(knob_dir / "normal/inputs.txt")
    knob_log = read(knob_dir / "normal/latency.log")
    evidence.append(checked_test(knob_dir / "normal/latency.log", "tb_review_knob_latency", "PASS tb_review_knob_latency:"))
    knob_values = re.search(r"max_settled_ns=(\d+) max_pair_ns=(\d+) min_scl_low_ns=(\d+) min_scl_high_ns=(\d+)", knob_log)
    if knob_values is None:
        raise SystemExit("Missing timed-knob observations")
    verify_manifest(knob_dir / "slow_wait/inputs.txt")
    if "FAIL knob latency" not in read(knob_dir / "slow_wait/latency.log"):
        raise SystemExit("Slow-wait negative control not rejected")
    strict_count = verify_manifest(ROOT / "build/regression/strict/strict_inputs.txt")
    if re.search(r"\*\* (Error|Fatal):", read(ROOT / "build/regression/strict/strict_compile.log")):
        raise SystemExit("Strict compilation failed")
    negative_dir = ROOT / "build/regression/review"
    verify_manifest(negative_dir / "negative_Layout_inputs.txt")
    negative = read(negative_dir / "tb_review_layout_negative_Layout.log")
    if "FAIL native pixel" not in negative or "PASS tb_review_layout" in negative:
        raise SystemExit("Layout mutation not rejected")
    capacity_dir = ROOT / "build/regression/capacity"
    verify_manifest(capacity_dir / "negative_inputs.txt")
    capacity_negative = read(capacity_dir / "tb_review_uart_capacity_top_negative.log")
    if "FAIL capacity top byte" not in capacity_negative or "PASS tb_review_uart_capacity_top" in capacity_negative:
        raise SystemExit("Disconnected UART capacity parameter not rejected")
    dual_dir = ROOT / "build/regression/dual"
    verify_manifest(dual_dir / "negative_inputs.txt")
    dual_negative = read(dual_dir / "tb_review_dual_system_negative.log")
    if "FAIL dual synthesis guitar selection not connected" not in dual_negative or "PASS tb_review_dual_system" in dual_negative:
        raise SystemExit("Disconnected guitar synthesis selector not rejected")
    reset_dir = ROOT / "build/regression/hdmi_reset"
    verify_manifest(reset_dir / "negative_inputs.txt")
    reset_negative = read(reset_dir / "tb_review_hdmi_reset_recovery_negative.log")
    if ("CASE HDMI reset recovery epoch=0 " not in reset_negative
            or "FAIL HDMI reset word alignment epoch=1" not in reset_negative
            or "PASS tb_review_hdmi_reset_recovery" in reset_negative):
        raise SystemExit("Post-recovery lane corruption not rejected")
    reset_normal = read(reset_dir / "tb_review_hdmi_reset_recovery_normal.log")
    if len(re.findall(r"CASE HDMI reset recovery epoch=\d+ checked_words=", reset_normal)) != 17:
        raise SystemExit("Incomplete reset recovery epochs")
    reset_protected = json.loads(read(ROOT / "build/review/hdmi_reset_baseline/protected_inputs.json"))
    # 10月16日用户明确授权15路外设迁到31005/J13；只准许这一个CST的精确位置变更。
    # 旧保护清单不改写，SDC/HDMI布局/process/队友TB仍逐文件校验原哈希。
    pin_contract, pin_migration = validate_cst()
    migrated_cst = (ROOT / pin_contract["cst"]).resolve()
    authorised_protected_changes = []
    for item in reset_protected:
        if sha(Path(item["path"])) != item["sha256"].lower():
            if (Path(item["path"]).resolve() == migrated_cst
                    and item["sha256"].lower() == pin_contract["previous_cst_sha256"]):
                authorised_protected_changes.append(item["path"])
            else:
                raise SystemExit(f"Protected TB/constraint/config changed: {item['path']}")
    reset_netlist = ROOT / "projects/hdmi/impl/gwsynthesis/piano_hdmi.vg"
    # 保留此前局部复位布局；132份历史保护清单中仅piano.cst按上方精确合同授权迁移。
    # 用当前网表、实际落点及同输入复构建证据检查新引脚实现，不改写旧保护清单。
    netlist_body = read(reset_netlist)
    if (len(re.findall(r'LUT2 \\g_lane\[\d\]\.u_reset_combine\s', netlist_body)) != 4
            or len(re.findall(r'DFFCE \\g_lane\[\d\]\.serializer_release_[01]_s0\s', netlist_body)) != 8
            or len(implementation.get("reset_placement", {})) != 12):
        raise SystemExit("Local reset topology/placement not verified")
    placement_trial_dir = ROOT / "build/review/hdmi_reset_placement_trial"
    verify_manifest(placement_trial_dir / "build_inputs.txt")
    placement_trial = json.loads(read(placement_trial_dir / "implementation_check.json"))
    if (placement_trial["status"] != "PASS_CURRENT_CONSTRAINTS_ONLY"
            or sha(placement_trial_dir / "piano_hdmi.fs") != placement_trial["bitstream_sha256"]
            or sha(placement_trial_dir / "build_inputs.txt") != sha(ROOT / "build/hdmi/build_inputs.txt")
            or sha(placement_trial_dir / "build.log") == sha(ROOT / "build/hdmi/build.log")
            or placement_trial["bitstream_sha256"] == implementation["bitstream_sha256"]):
        raise SystemExit("Missing distinct repeated HDMI build with identical inputs")
    for key in ("resources", "worst_reported_slack_ns", "reset_placement"):
        if placement_trial[key] != implementation[key]:
            raise SystemExit(f"HDMI repeated physical result differs: {key}")
    first_payload = re.sub(r"(?m)^//Created Time:[^\r\n]*\r?\n", "", read(placement_trial_dir / "piano_hdmi.fs"))
    second_payload = re.sub(r"(?m)^//Created Time:[^\r\n]*\r?\n", "", read(artifact))
    if first_payload != second_payload:
        raise SystemExit("Repeated bitstream differs beyond creation timestamp")
    placement_checks = ROOT / "build/regression/hdmi_placement"
    verify_manifest(placement_checks / "inputs.txt")
    for case, expected in (("placement", "Reset placement missing/moved:"),
                           ("thin_margin", "Reset optimization margin below 0.100ns:")):
        if expected not in read(placement_checks / f"{case}.log"):
            raise SystemExit(f"Physical checker negative control missing: {case}")
    verify_manifest(dual_dir / "host_inputs.txt")
    for filename, count in (("host_existing.log", 53), ("host_cases.log", 4)):
        host_body = read(dual_dir / filename)
        if f"Ran {count} tests" not in host_body or not re.search(r"(?m)^OK\s*$", host_body) or "FAILED" in host_body:
            raise SystemExit(f"Dual host compatibility failed: {filename}")
    protected = ["upstream/fpga_interaction", "verification/tb/control", "verification/tb/audio", "verification/tb/synth", "verification/tb/integration"]
    subprocess.run(["git", "diff", "--exit-code", "--", *protected], cwd=ROOT, check=True, capture_output=True)
    frame = ROOT / "build/regression/hdmi/hdmi_frame.hex"
    before_ui = old.get("before_native_ui") or {
        key: old["implementation"][key] for key in ("resources", "worst_reported_slack_ns", "bitstream_sha256")
    }
    before_knobs = old.get("before_fast_knobs") or {
        key: old["implementation"][key] for key in ("resources", "worst_reported_slack_ns", "bitstream_sha256")
    }
    summary = {
        "baseline": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "date": "2026-10-16",
        "review_skill": "fpga-development",
        "visual_skill": "canvas-design",
        "quality_score": 8 if implementation_passed else 7,
        "release_status": "CANDIDATE_NOT_HARDWARE_VERIFIED" if implementation_passed else "NOT_READY_TIMING_FAILURE",
        "implementation": implementation,
        "before_native_ui": before_ui,
        "before_fast_knobs": before_knobs,
        "before_quiet_ui": old.get("before_quiet_ui") or {
            key: old["implementation"][key] for key in ("resources", "worst_reported_slack_ns", "bitstream_sha256")
        },
        "strict_verilog_sources": strict_count,
        "board_pin_migration": pin_migration,
        "regression_pass_counts": {**{key: len(value) for key, value in suites.items()}, "all": 27, "performance": 5, "timed_knob": 1},
        "tests": evidence,
        "negative_control": "Native white-key width 120->119 rejected by boundary pixel checker",
        "audio_negative_controls": audio_mutations,
        "knob_response": {
            "cases": 9, "maximum_observed_ns": int(knob_values[1]), "maximum_pair_period_ns": int(knob_values[2]),
            "minimum_scl_low_ns": int(knob_values[3]), "minimum_scl_high_ns": int(knob_values[4]),
            "endpoint": "audio-domain gain/bend ramp settled, not analog audio output",
            "adc_model": "1.35ms conversion, input captured at conversion start; steady-state phase sweep",
            "negative_control": "10ms-per-channel wait rejected by 10ms parameter deadline",
            "hardware_measured": False,
        },
        "frame": {"path": frame.relative_to(ROOT).as_posix(), "sha256": sha(frame), "size": [1024, 600], "waveform": "test sawtooth, not recorded piano"},
        "changes": ["31005 confirmed: 13 keys + ADC SDA/SCL moved to J13; J8/J9 supply 3.3V/GND only", "RTL, teammate TB, SDC and process unchanged in pin migration; new physical implementation required", "Prior native quiet piano/guitar UI and shared 16-voice synthesis preserved", "Dual audio R0..R7 alignment; display P0/P1/P2 unchanged", "Prior local two-stage reset FF/LUT placement retained without timing exceptions"],
        "uart_capacity": {"production_voices": 16, "default_voices": 4,
                          "tested_capacities": [1, 4, 9, 10, 16, 32], "tone_variants": 3,
                          "negative_control": "Disconnected VOICES parameter rejected by exact production UART byte checker"},
        "prior_audio_regression": "J13 migration reran performance5 + HDMI4 + reset1; remaining 49 FPGA checks and host53+4 retained with exact unchanged dependency hashes, not claimed rerun. Other older piano/PA results are not claimed current here",
        "dual_instruments": {"mode_key": "KEY2", "reset_mode": "piano", "shared_voices": 16,
                             "physical_keys": 13, "old_voice_timbre_preserved": True, "sample_cache_cycle": "R7",
                             "guitar_frame_path": "build/regression/hdmi/hdmi_guitar_frame.hex",
                             "guitar_frame_sha256": sha(ROOT / "build/regression/hdmi/hdmi_guitar_frame.hex"),
                             "before_shift_optimization": json.loads(read(dual_dir / "before_shift_implementation.json"))["resources"],
                             "host_tests": 57, "host_source_manifest_sha256": sha(dual_dir / "host_inputs.txt")},
        "hdmi_reset_recovery": {
            "epochs": 17, "words_checked_per_epoch_min": 128, "serial_bit_phases": 10,
            "cases": ["power-on", "HPD reconnect/bounce", "PLL unlock", "serial/both clocks paused", "system/PLL reset"],
            "vendor_model": "installed Gowin GW5A PLLA/OSER10, not analog metastability or electrical timing",
            "negative_control": "Initial startup passed, red lane corrupted only after first recovery rejected",
            "before": json.loads(read(ROOT / "build/review/hdmi_reset_baseline/implementation_check.json")),
            "protected_files": len(reset_protected) - len(authorised_protected_changes),
            "baseline_protected_files": len(reset_protected),
            "authorised_pin_constraint_changes": authorised_protected_changes,
            "constraints_relaxed": False,
            "optimization_status": "IMPROVED_LOCAL_IO_PLACEMENT", "netlist_sha256": sha(reset_netlist),
            "display_startup_extra_pixel_cycles": 1, "audio_cache_cycle": "R7 unchanged",
            "placement_constraint": "boards/tang_mega_60k_31004/hdmi_reset_placement.cst",
            "placement_cells": implementation["reset_placement"],
            "minimum_reset_margin_gate_ns": 0.100,
            "repeat_build": {"count": 2, "identical_input_manifest": True,
                             "identical_resources_slacks_placement": True,
                             "identical_bitstream_except_created_time": True,
                             "first_bitstream_sha256": placement_trial["bitstream_sha256"],
                             "second_bitstream_sha256": implementation["bitstream_sha256"],
                             "first_build_log_sha256": sha(placement_trial_dir / "build.log"),
                             "second_build_log_sha256": sha(ROOT / "build/hdmi/build.log")},
            "implementation_negative_controls": ["misplaced reset cell", "positive but 0.008ns thin removal margin"],
            "rejected_serial_domain_trial": {
                key: json.loads(read(ROOT / "build/review/hdmi_reset_serial_trial/implementation_check.json"))[key]
                for key in ("status", "errors", "worst_reported_slack_ns", "bitstream_sha256")
            },
            "polarity_only_trial": {
                key: json.loads(read(ROOT / "build/review/hdmi_reset_polarity_trial/implementation_check.json"))[key]
                for key in ("status", "worst_reported_slack_ns", "bitstream_sha256")
            },
            "rejected_combined_state_trial": {
                key: json.loads(read(ROOT / "build/review/hdmi_reset_combined_trial/implementation_check.json"))[key]
                for key in ("status", "errors", "worst_reported_slack_ns", "bitstream_sha256")
            },
        },
        "existing_teammate_tests_modified": False,
        "hardware_programmed": False,
        "github_pushed_this_round": False,
        "no_screen_implementation": no_screen_result(),
        "summarizer_sha256": sha(Path(__file__)),
    }
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not implementation_passed:
        raise SystemExit(f"RECORDED FAILED HDMI implementation; {strict_count} strict sources and {len(evidence)} functional self-checks verified. NOT ready to release.")
    print(f"PASS HDMI evidence: {strict_count} strict sources, {len(evidence)} current self-checks, source hashes verified")


if __name__ == "__main__":
    main()
