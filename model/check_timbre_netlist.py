"""Audit the two-timbre Gowin synthesis netlist without modifying tool outputs.

Checks every INIT word, the 16-bit selector truth tables, selector register,
and hierarchical connections through the envelope multiplier for each voice.
This audit targets the saved Gowin 1.9.12.03 configuration and generated names.
An unexpected hierarchy or cell change deliberately fails for human review.
This is a structural audit, not a post-route gate-level simulation.
"""
from pathlib import Path
import argparse
import hashlib
import itertools
import json
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--netlist", type=Path,
                    default=ROOT / "projects/checks/poly_adsr_check/impl/gwsynthesis/poly_adsr_check.vg",
                    help="Gowin synthesis .vg; matching .log must be in the same directory")
parser.add_argument("--report", type=Path,
                    default=ROOT / "build/regression/logs/timbre_netlist_audit.json",
                    help="JSON audit result (created only when every check passes)")
args = parser.parse_args()
NETLIST = args.netlist.resolve()
text = NETLIST.read_text(encoding="utf-8")
modules = dict(re.findall(r"(?ms)^module\s+(\w+)\s*\((.*?)^endmodule[^\n]*", text))
rom_tables = {}
for label, path in (("soft", "sine_1024.mem"), ("bright", "bright_1024.mem")):
    source = ROOT / "rtl/rom" / path
    words = [int(x, 16) for x in source.read_text(encoding="ascii").split()]
    assert len(words) == 1024
    rom_tables[label] = words


def block(body, kind, instance):
    match = re.search(r"\b" + re.escape(kind) + r"\s+" + re.escape(instance) + r"\s*\((.*?)\);", body, re.S)
    assert match, (kind, instance)
    return dict((p, re.sub(r"\s+", "", n)) for p, n in re.findall(r"\.([\w]+)\(([^)]*)\)", match[1]))


records = []
for voice, suffix in enumerate(("", "_0", "_1", "_2")):
    mem_name = "wave_lut" + suffix
    wave_name = "wave_lut_timbre" + suffix
    voice_name = "voice_timbre_adsr" + suffix
    mem, wave, sound = modules[mem_name], modules[wave_name], modules[voice_name]
    for label, instance in (("soft", "rom_rom_0_0_s"), ("bright", "rom_rom_0_1_s")):
        blocks = re.findall(r"defparam\s+" + instance + r"\.INIT_RAM_([0-9A-Fa-f]{2})=256'h([0-9A-Fa-f]+);", mem)
        assert len(blocks) == 64
        decoded = []
        for expected_index, (index, data) in enumerate(blocks):
            assert int(index, 16) == expected_index
            bits = int(data, 16)
            decoded.extend((bits >> (16 * offset)) & 0xFFFF for offset in range(16))
        assert decoded == rom_tables[label], (voice, label, "ROM contents differ")
        pins = block(mem, "pROM", instance)
        assert label + "_sample[15:0]" in pins["DO"]
        assert pins["CE"] == "sample_request_q"
        assert pins["AD"] == "{addr[9:0],GND,GND,VCC,VCC}"
        records.append({"voice": voice, "kind": label, "module": mem_name,
                        "instance": instance, "words": len(decoded), "source_match": True})
    assert rom_tables["soft"] != rom_tables["bright"]
    decoded_mux_bits = []
    for bit in range(16):
        inst = f"raw_sample_{bit}_s"
        pins = block(wave, "LUT3", inst)
        init = int(re.search(r"defparam\s+" + inst + r"\.INIT=8'h([0-9A-Fa-f]+);", wave)[1], 16)
        assert pins["F"] == f"raw_sample[{bit}]"
        assert {pins[f"I{x}"] for x in range(3)} == {
            f"soft_sample[{bit}]", f"bright_sample[{bit}]", "selected_bright"}
        for soft, bright, select in itertools.product((0, 1), repeat=3):
            values = {f"soft_sample[{bit}]": soft, f"bright_sample[{bit}]": bright,
                      "selected_bright": select}
            index = sum(values[pins[f"I{x}"]] << x for x in range(3))
            assert (init >> index) & 1 == (bright if select else soft), (voice, bit, values)
        decoded_mux_bits.append(bit)
    select = block(wave, "DFFRE", "selected_bright_s0")
    assert select["Q"] == "selected_bright" and select["D"] == "read_bright"
    assert select["CE"] == "sample_request_q" and select["CLK"] == "clk_d"
    rom_call = block(wave, mem_name, "u_soft")
    assert rom_call["soft_sample"] == "soft_sample[15:0]"
    assert rom_call["bright_sample"] == "bright_sample[15:0]"
    wave_call = block(sound, wave_name, "u_wave")
    assert wave_call["raw_sample"] == "raw_sample[15:0]"
    assert wave_call["read_bright"] == "read_bright"
    # The mux output still drives the original registered ADSR multiplier.
    gain_type = "sample_gain" if voice == 0 else f"sample_gain_{2*voice-1}"
    gain_call = block(sound, gain_type, "u_gain")
    assert gain_call["raw_sample"] == "raw_sample[15:0]"
    # Selection is dynamic from this voice's own registered timbre control.
    pending = block(sound, "DFFRE", "pending_timbre_s0")
    assert pending["D"] == f"timbre_q[{voice}]"
    assert re.search(r"\.I\d\(timbre_q\[" + str(voice) + r"\]\)", sound)
    select_logic = block(sound, "LUT4", "read_bright_s0")
    assert select_logic["F"] == "read_bright"
    assert "event_timbre" in select_logic.values() and "active_timbre" in select_logic.values()

assert len(re.findall(r"(?m)^\s+pROM\s", text)) == 8
warnings = NETLIST.with_suffix(".log").read_text(encoding="utf-8")
swept = [line for line in warnings.splitlines() if "NL0002" in line and "u_bright" in line]
assert len(swept) == 4
report = {
    "netlist": str(NETLIST),
    "netlist_sha256": hashlib.sha256(NETLIST.read_bytes()).hexdigest(),
    "status": "PASS",
    "scope": "Synthesis-netlist structural/content audit; not post-route simulation",
    "roms": records,
    "total_rom_words_verified": 8192,
    "selected_data_mux_bits_verified": 64,
    "mux_truth_table_combinations_verified": 512,
    "independent_dynamic_selector_registers_verified": 4,
    "connections_to_adsr_multiplier_verified": 4,
    "bright_hierarchy_warning_count": len(swept),
    "conclusion": "Both physical pROMs were placed under each u_soft module; only u_bright hierarchy was removed. All bright data and selector paths remain."
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("PASS: 8 pROMs retain 8192/8192 exact source words (4 sine + 4 bright).")
print("PASS: 64 output LUT mux bits, 512 truth-table cases, 4 dynamic selector registers, 4 ADSR multiplier connections.")
print("Resolved: 4 NL0002 u_bright warnings remove module hierarchy; both pROMs live under each u_soft module.")
print("Netlist SHA256:", report["netlist_sha256"])
print("Report:", args.report.resolve())
