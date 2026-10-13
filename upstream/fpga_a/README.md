# FPGA A：实时合成引擎仿真模型

本目录是 A 部分的服务于 C 仿真的简化实现。

## RTL

- `rtl/phase_inc_calc.v`：音符号转换为 32 位相位增量，按 48 kHz 计算。
- `rtl/wave_lut.v`：256 点 16 位正弦波表。
- `rtl/adsr_envelope.v`：带 Attack、Decay、Sustain、Release 的包络，并产生 release_done。
- `rtl/voice_gain.v`：波表与包络相乘。
- `rtl/poly_mixer_saturator.v`：多声部混音和饱和输出。
- `rtl/synth_engine.v`：32 声部合成引擎，接收 C 部分声部总线。

## 生成文件

`tools/gen_tables.py` 会重新生成：

- `phase_inc_calc.v`
- `wave_lut.v`

运行：

```powershell
python D:\AI tools\Codex&GPT\files\fpga_a\tools\gen_tables.py
```