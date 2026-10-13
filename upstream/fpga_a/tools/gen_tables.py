import math
from pathlib import Path

root = Path(__file__).resolve().parents[1]
rtl = root / "rtl"
rtl.mkdir(parents=True, exist_ok=True)

# MIDI note -> 32-bit phase increment for 48 kHz sample rate.
lines = []
lines.append("`timescale 1ns/1ps")
lines.append("")
lines.append("module phase_inc_calc (")
lines.append("    input  wire [6:0] note,")
lines.append("    output reg  [31:0] phase_inc")
lines.append(");")
lines.append("")
lines.append("    always @* begin")
lines.append("        case (note)")
for note in range(128):
    freq = 440.0 * (2.0 ** ((note - 69) / 12.0))
    inc = int(round((freq * (2.0 ** 32)) / 48000.0))
    inc = max(1, min(inc, (1 << 32) - 1))
    lines.append(f"            7'd{note}: phase_inc = 32'd{inc};")
lines.append("            default: phase_inc = 32'd0;")
lines.append("        endcase")
lines.append("    end")
lines.append("")
lines.append("endmodule")
(rtl / "phase_inc_calc.v").write_text("\n".join(lines) + "\n", encoding="utf-8")

# 256-point sine table plus simple triangle/saw/square timbres.
lines = []
lines.append("`timescale 1ns/1ps")
lines.append("")
lines.append("module wave_lut (")
lines.append("    input  wire [7:0] addr,")
lines.append("    input  wire [1:0] wave_sel,")
lines.append("    output reg signed [15:0] sample")
lines.append(");")
lines.append("")
lines.append("    reg signed [15:0] sine_sample;")
lines.append("")
lines.append("    always @* begin")
lines.append("        case (addr)")
for i in range(256):
    val = int(round(32767.0 * math.sin(2.0 * math.pi * i / 256.0)))
    if val < 0:
        lines.append(f"            8'd{i}: sine_sample = -16'sd{-val};")
    else:
        lines.append(f"            8'd{i}: sine_sample = 16'sd{val};")
lines.append("            default: sine_sample = 16'sd0;")
lines.append("        endcase")
lines.append("    end")
lines.append("")
lines.append("    always @* begin")
lines.append("        case (wave_sel)")
lines.append("            2'd0: sample = sine_sample;")
lines.append("            2'd1: sample = (addr < 8'd128) ? ((addr << 8) - 16'sd32768) : ((addr << 8) - 16'sd65536);")
lines.append("            2'd2: sample = (addr < 8'd64) ? (addr * 16'sd512) : ((addr < 8'd192) ? (16'sd16384 - ((addr - 8'd64) << 9)) : (((addr - 8'd192) << 9) - 16'sd32768));")
lines.append("            default: sample = (addr < 8'd128) ? 16'sd32767 : -16'sd32768;")
lines.append("        endcase")
lines.append("    end")
lines.append("")
lines.append("endmodule")
(rtl / "wave_lut.v").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("generated phase_inc_calc.v and wave_lut.v")