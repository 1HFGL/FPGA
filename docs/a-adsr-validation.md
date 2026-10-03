# 单声部 ADSR v2：验证与交接记录

日期：2026-10-01。此记录对应 `feat/a-dds-core` 分支本次单声部升级，面向 A/B/C 集成使用。

后续更新：2026-10-03 在相同 50 MHz 约束下优化关键路径，Setup 裕量提高到 +8.265 ns；8 项回归与 Python 对照重新通过。最新结果见 [时序优化记录](a-adsr-timing-20261003.md)。本文其余内容保留为 10 月 1 日的历史证据。

## 这次交付什么

将固定步长包络升级为按采样点数定时的线性 ADSR，保持原有信号端口与音频流水线。默认采样率 48 kHz 时，A=96 点（2 ms）、D=24000 点（500 ms）、S=6554/65536（约 10% 幅度）、R=5760 点（120 ms）。

从任意非零当前电平释放都计满 R 个采样点；提前松键、释放中再按、重触发暂存和复位已覆盖。三份 RTL 加入中文注释，说明参数单位、阶段转换、位宽、舍入和输出有效时刻。

本次不新增波形、不实现四声部混音，也不代表真实乐器音色或整机上板已经验收。

## 功能仿真

工具：ModelSim SE-64 10.6e，独立 Python 整数/正弦参考模型。

| 检查 | 实际结果 |
| --- | --- |
| A/B 原有测试与 ADSR 测试 | 8 个测试平台全部通过，最终日志均为 0 Error / 0 Warning |
| 包络定向与边界 | 7 组参数、1614924 项检查通过 |
| 音量乘法 | 458757 项检查通过，包括所有 16 位输入在 7 种增益下的穷举 |
| 单声部与流水线 | 162085 个时钟、47734 个有效样本匹配 |
| Python 独立对照 | 同样本数通过，14 个复位周期、5 个状态、A/D/R 完成时长均匹配 |
| 原 DDS Python 对照 | 1024 个波表值、4810 个样本、6 个复位记录通过 |

复现命令（在仓库根目录，替换为各自的工具路径）：

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'D:\modelsim1\win64'
python model/check_adsr.py
python model/check_dds.py
```

## 高云综合与布局布线

用户在本机高云工程中运行工具；本记录依据生成的原始文件核对，不依据绿色图标推断。

| 条件 | 值 |
| --- | --- |
| 工具 | Gowin V1.9.12.03（64-bit） |
| 器件 | GW5AT-LV60PG484AC1/I0 |
| 顶层 | `voice_adsr` |
| 综合完成 | 2026-10-01 22:59:45，波表缺失及相位累加器被清除的警告已消失 |
| 最新布局布线/时序报告 | 2026-10-01 23:20:59 |
| 时钟约束 | `create_clock -name sys_clk -period 20.000 [get_ports {clk}]` |
| Setup / Hold 违例端点 | 0 / 0 |
| 最差 Setup / Hold 裕量 | +0.352 ns / +0.247 ns |
| 最差最小脉宽裕量 | +6.940 ns |
| 工具估算 Fmax | 50.895 MHz |
| 已分析路径 / 端点 | 1391 / 533 |
| 布线后资源 | 561 LUT、115 ALU、146 寄存器、1 BSRAM、1 DSP |

结论：**当前单声部实现完成综合和布局布线，在 50 MHz 时钟约束下已报告的内部时序检查通过。** 最紧的路径位于包络电平更新逻辑，Setup 余量仅 0.352 ns，整机集成/扩展声部后必须重新验证。

约束范围：这次只有 `create_clock`，没有板级物理引脚约束、输入/输出延迟约束，报告也没有未约束路径数量统计。Recovery/Removal 显示无可报告路径。不能据此声明整机 I/O、引脚、异步输入、DAC 输出或上板试听全部通过；本次独立模块工程的位流不应作为整机下载文件。

原始证据已经从忽略的 `build/` 目录复制到可提交位置：

- [时序报告原文](reports/adsr_v2_20261001/timing.html)（下载后用浏览器打开可查看表格）。
- [布局布线及资源报告原文](reports/adsr_v2_20261001/place_route.txt)。
- [综合日志原文](reports/adsr_v2_20261001/synthesis.log)。
- [本次 50 MHz 时钟约束](reports/adsr_v2_20261001/clock.sdc)。
- [报告及综合时源码 SHA-256](reports/adsr_v2_20261001/manifest.json)。

报告保留工具生成时的本机路径，仅作证据，不是队友应照抄的工程路径。综合时顶层 ROM_FILE 曾临时使用本机绝对路径；提交准备时仅将其默认字符串恢复为 `rtl/rom/sine_1024.mem`，指向同一份波表，未改变运算逻辑。发布后的工程仍需正确解析 ROM 路径，不能将旧报告当成任意新工程的自动验收。

## 提交前的路径复核

恢复相对 ROM 默认值后，单声部 ModelSim 与 Python 对照再次通过（162085 个时钟、47734 个样本）。在独立的临时高云工程中，以仓库根目录作为 Include Path 再次综合通过，日志无 WARN/ERROR，资源与原综合一致；[复核日志](reports/adsr_v2_20261001/portable_synthesis.log)已保存。未覆盖前述 23:20:59 的布局布线报告，也没有将这次仅综合复核写成一次新的时序验收。

## 队友接入要注意什么

1. 添加 `phase_acc.v`、`wave_lut.v`、`voice_dds.v`、`adsr_env.v`、`sample_gain.v`、`voice_adsr.v` 六份 RTL，保留 `rtl/rom/sine_1024.mem`。
2. 信号端口保持。三个参数从 `ATTACK_STEP/DECAY_STEP/RELEASE_STEP` 改为 `ATTACK_SAMPLES/DECAY_SAMPLES/RELEASE_SAMPLES`，单位改为采样点；旧步长值不能直接搬过来。`SUSTAIN_LEVEL` 为 17 位无符号幅度。
3. `gate` 是已同步/消抖的按住状态；`retrigger` 为单时钟脉冲，不用时接 0。松键以后必须继续送 `sample_tick`，否则释放过程会停止。
4. 声音输出以 `sample_valid` 为准，DDS 后增加一拍乘法延迟；整机接收时刻见 [接口说明](a-adsr.md)。
5. 高云解析 ROM 时会查源文件目录、项目目录及 Include Path（官方 GowinSynthesis User Guide SUG550-2.4E，第 4.5 节）。在 Synthesize → Configuration 中将 **Include Path** 添加为各自的仓库根目录，例如 `C:/Users/你的用户名/Documents/GitHub/FPGA`；这样默认 `rtl/rom/sine_1024.mem` 能正确解析。不要添加到 `rtl` 或 `rtl/rom` 这一层。CLI 对应 `set_option -include_path {仓库根目录}`。项目当前本机 IncludePath 配置已补充；已打开的高云工程应重新打开以加载磁盘设置，随后确认综合日志没有 `Cannot open file`。
6. 将模块接入 B 的实际板级顶层后，检查真实时钟、全部接口/引脚约束，重新综合、布局布线与试听。当前报告不替代这一步。
