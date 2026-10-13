# A：拨弦与弦乐两种合成预设

本次升级的目的，是让两种声音在起音、持续和松键时都有可解释的区别。`voice_bank_instruments` 是新的四声部核心：0 为吉他拨弦感，1 为弦乐持续感。它们是用单周期波表实时合成的预设，不是录音乐器采样，也不宣称能精确复刻原声吉他或弦乐。原 `voice_bank_adsr` 的柔和／明亮模式及旧测试保持不变，便于对照。

## 声音如何变化

每声部使用一张共同的正弦表与一张所选乐器表，再按时间改变乐器表相对基波的比例，最后应用 ADSR、力度和混音。这样既改变总体音量，也改变谐波组成。

| 项目 | 0：拨弦感 | 1：弦乐感 |
|---|---|---|
| 起音 A | 64 点，约 1.33 ms | 1024 点，约 21.33 ms |
| 衰减 D | 32768 点，约 682.67 ms | 8192 点，约 170.67 ms |
| 保持 S | 0，按住也会自然衰减到静音 | 49152/65536，即 75% |
| 松键释放 R | 4096 点，约 85.33 ms | 8192 点，约 170.67 ms |
| 谐波亮度 | 8192 点内从 1 降到 1/16 | 2048 点内从 1/8 升到 1/2 |

时间按 48 kHz 采样率换算；参数本身以采样点计数。更换采样率必须同时更新 MIDI 步长表和时间参数。0 点时长按 1 点处理，保持电平高于 65536 时钳位到 65536。

ADSR 是线性幅度曲线；亮度变化采用两组谐波的线性插值，**不是递归低通滤波器**。本轮没有加入混响、延迟、颤音或全局音量平滑。

`model/gen_instrument_roms.py` 以可复算公式生成 1024 点、16 位有符号波表：

```text
theta = 2*pi*address/1024
full  = round_half_away_from_zero(32767/32 * sum(w[h]*sin(h*theta)))
Guitar  h=1..8: 16,8,4,0,2,1,1,0
Strings h=1..8: 16,6,3,2,2,1,1,1
```

两表权重和都为 32，基波目标幅度一致。播放时 `base=floor(sine/2)`，`shaped=base+floor((full-base)*tone/65536)`；由于 `tone` 在 0 到 65536 之间，插值不会越过两个端点。所有乘法先扩位再作带符号算术右移。负数向下取整会带来微小量化偏置，因此不能将量化后的全部输出宣称为严格零直流。

当 `phase_inc >= 0x10000000` 时，采用相同半幅基波作为 `full`，避免这两张表的高次谐波越过奈奎斯特频率；48 kHz 下对应 3 kHz 及以上。这个保守保护覆盖最高八次谐波，不是全音域的完美抗混叠算法。C4～C5 保留两种谐波音色。

## 源文件与综合

新模块的职责：

- `rtl/synth/instrument_env.v`：两个预设共用一个包络状态，从当前幅度重新起音或释放。
- `rtl/synth/instrument_wave.v`：同步读取正弦、拨弦、弦乐波表，并选择本声部的乐器。
- `rtl/synth/voice_instrument.v`：独立相位、事件锁存、亮度进程、ADSR 乘法。
- `rtl/synth/voice_bank_instruments.v`：四个独立声部、力度快照、饱和混音、释放反馈。

依赖原有 `phase_acc.v`、`wave_lut.v`、`sample_gain.v`、`sample_mixer4.v`、`note_phase_lut.v`，以及 `rtl/rom/sine_1024.mem`、`guitar_1024.mem`、`strings_1024.mem`。不要把 `verification/tb/` 或 `upstream/` 中的测试平台加入高云综合。

独立高云验证工程为 `projects/checks/instruments_check/instruments_check.gprj`。顶层是 `voice_bank_instruments_timing_top`，使用实际 GW5AT-LV60PG484AC1/I0 器件与 20 ns 时钟约束，在核心前后注册同步接口。工程脚本从自身路径定位仓库，避免绝对 ROM 路径。

这个外壳用于验证模块间寄存器路径；没有板级 CST，**不能直接下载到板卡**。B 集成到实际顶层后，仍须重新跑整机综合、布局布线、约束覆盖与音频链路测试。

## 给 B/C 的接口约定

四路 `voice_note_flat[27:0]`、`voice_velocity_flat[27:0]` 都是每声部 7 位，声部 0 在最低位。`voice_gate[3:0]` 表示保持；`voice_retrigger[3:0]` 是同一系统时钟内的触发脉冲。低有效 `rst_n` 为同步复位。跨时钟或机械按键的同步、消抖在上层完成。

新输入 `voice_instrument[3:0]` 每路一位，0=拨弦、1=弦乐。若 C 仍输出四路各 4 位的音色 ID，总线必须逐槽解码：

```verilog
// voice_timbre_flat 是 C 的 16 位总线示例名称，以实际接口名为准。
assign voice_instrument[0] = (voice_timbre_flat[3:0]   == 4'd1);
assign voice_instrument[1] = (voice_timbre_flat[7:4]   == 4'd1);
assign voice_instrument[2] = (voice_timbre_flat[11:8]  == 4'd1);
assign voice_instrument[3] = (voice_timbre_flat[15:12] == 4'd1);
```

这段适配将未支持的 ID 回退为 0；团队可另约定错误处理，不能直接截取总线低 4 位。`instrument_active[3:0]` 是各声部已采纳的乐器，`env_level_flat` 和 `tone_level_flat` 各 68 位，每路 17 位，只供调试。

自然起音或重触发时才采纳乐器；保持及旧尾音不会跟随选择开关变化。采样间收到的触发会暂存其乐器，多个事件以最后一个为准；采样同拍新触发优先，低 gate 优先于所有触发。S=0 的按住声部仍属于保持状态，不会无限自动重新起音。重触发保留当前幅度和连续相位，但更换波形可能产生瞬态，仍需上板试听调参。

| 时刻 | 当前请求对应的数据 |
|---|---|
| R0 | 接受请求，读旧相位波表，推进包络与亮度，快照力度 |
| R1 | 谐波亮度乘法，保存对应包络 |
| R2 | ADSR 乘法得到单声部样本 |
| R3 | 每声部力度缩放 |
| R4 | 饱和混音，`sample_valid=1`，输出 16 位有符号样本 |
| R5 | 同步下游寄存器可采到 R4 的有效样本 |

因此新核心请求到输出为 **4 个时钟间隔**，50 MHz 下为 80 ns；较旧双音色核心增加 1 拍。这个数字不是整机演奏延迟。B 必须按 `sample_valid` 接收，不能沿用固定 R3 假设。支持每个时钟连续请求；正常 48 kHz 请求由 B 产生。

力度 0 静音，127 为单位增益，1～126 为 velocity/128。默认 `MIX_SHIFT=5` 保留旧接口音量余量，可通过 `sample_clipped` 观察饱和。最终音量由整机设计确认。松键和静音时仍须持续提供 `sample_request`，否则包络和尾音无法推进。C 只有收到对应 `release_done` 后才能判定自然尾音结束；每路反馈覆盖新增流水级，不依据总混音为零来回收声部。

## 复现测试与试听

在仓库根目录 PowerShell 运行：

```powershell
.\verification\scripts\run_tests.ps1 -Suite Instruments -ModelSimBin 'D:\modelsim1\win64'
python model/gen_instrument_roms.py --check
python model/check_instrument_roms.py
python model/check_instrument_bank.py
python model/render_instrument_preview.py --capture build/regression/logs/instrument_preview.csv --out-dir docs/reports/legacy/audio --report build/regression/logs/instrument_preview_report.json
```

2026-10-11集成后，`-Suite Instruments` 为3个测试平台，`A`为15个，`All`为34个；UART和钢琴另有独立入口。全部有效测试使用Verilog-2001。ModelSim图形界面用 `source {仓库完整路径/verification/scripts/run_instruments.tcl}`，显示包络、亮度、已采纳乐器和混音输出。历史验证数量见下文，不与本次结果混用。

试听取自实际 RTL：两个 A4 长音各 2 秒，以及相同 C4/D4/E4/G4/C5 旋律各 2.5 秒，共 432000 点。Python 使用独立公式逐样本核对后才写 WAV，不用 Python 合成音频替代 RTL。为比较音色，每个预设使用一个固定播放增益，使两段旋律 RMS 对齐；该增益同时用于对应长音，不改变 FPGA 的音量逻辑。报告保存原始样本幅度、播放增益与峰值，WAV 是仿真试听，不是板卡录音。

本轮验证事实与原始证据见 [2026-10-08 验证记录](reports/instruments_20261008/README.md)。

下一步由 B 在实际烧录工程接入这个新核心，C 接每路乐器选择；先在同一音高、相近响度下试听按住、短按、四音和弦及松键尾音，再据实调参数。此前本地缓存中的 `origin/codex/adsr-integration` 为 `d909b178`，它仍采用旧声部；不能据此断定队友未提交的本地烧录源码与其相同。需要记录最终烧录版本，才能对比这次音色改进。
