# 单声部 ADSR 时序优化记录

日期：2026-10-03。基于 `feat/a-dds-core` 的 `b7ee567` 修改；当前为本地工作区结果。

组长指出原 Setup 裕量只有 0.352 ns，希望留出几 ns。优化 `rtl/adsr_env.v` 后，在相同器件、顶层、默认参数及 **20 ns / 50 MHz** 约束下重新运行高云综合和布局布线，最差 Setup 裕量提高到 **8.265 ns**。没有修改时钟周期，也没有添加 false path 或 multicycle path。

## 为什么变快

原实现把新段的距离除法、余数累加/比较、步长加一、幅度加减串在同一个组合通路中。原最紧路径是 `u_env/env_level[0]` 到 `env_level[16]`，24 层逻辑，数据延迟 19.591 ns。

这次保持余数分配算法，改为：

1. **单独处理每段第一步。** 起始误差是 0，余数 r 必定小于时长 N，所以第一步只走基本步长 q，不需要再经过余数进位判断。
2. **衰减初始化改用常量。** Decay 只从起音终点进入，起点必为 65536，因此距离 `65536-SUSTAIN_LEVEL` 和初始步长/余数可在综合期计算。
3. **后续步骤并行计算。** 幅度候选值与误差进位分别计算，然后选择最终幅度，缩短串联逻辑。
4. **按参数决定计数器位宽。** 默认最大时长 24000 点，只需 15 位；误差相加保留第 16 位进位。参数仍支持 32 位无符号数，不固定截成 15 位。

接口、默认 A/D/S/R 参数、重触发与松键优先级均保持。每次 `sample_tick` 当拍更新包络，连续请求仍可每拍输出样本；没有增加流水线延迟。第 k 步仍满足闭式直线 `floor(distance*k/N)`，最后一步精确到终点。

## 布线后的实际结果

工具：Gowin V1.9.12.03 (64-bit)，器件 GW5AT-LV60PG484AC1/I0，顶层 `voice_adsr`。本次报告时间：2026-10-03 14:50:32。默认参数 A=96、D=24000、S=6554、R=5760，ROM 使用仓库相对路径，Include Path 为仓库根目录。

| 项目 | 原版本（2026-10-01） | 优化后（2026-10-03） |
| --- | --- | --- |
| 时钟周期 / 频率 | 20 ns / 50 MHz | 20 ns / 50 MHz |
| 最差 Setup 裕量 | +0.352 ns | **+8.265 ns** |
| 最差 Hold 裕量 | +0.247 ns | +0.247 ns |
| Setup / Hold 违例端点 | 0 / 0 | 0 / 0 |
| 最小脉宽裕量 | +6.940 ns | +6.940 ns |
| 工具估算 Fmax | 50.895 MHz | 85.216 MHz |
| 最紧路径数据延迟 | 19.591 ns | 11.678 ns |
| 最紧路径逻辑层数 | 24 | 16 |
| LUT / ALU | 561 / 115 | 362 / 126 |
| 寄存器 | 146 | 111 |
| BSRAM / DSP | 1 / 1 | 1 / 1 |
| 已分析路径 / 端点 | 1391 / 533 | 1211 / 428 |

Setup 增加了 7.913 ns 裕量；这项是组长所说的长组合路径优化。Hold 是另一项最小延迟检查，目前保持正裕量且没有违例，不要求它也随 Setup 增加同样的 ns。

新的最紧路径仍位于包络，起点 `u_env/env_level_16_s0/Q`，终点 `u_env/env_level_15_s0/D`。综合日志没有 WARN/ERROR，波表与相位累加器保留，1 BSRAM、1 DSP 仍在。

## 功能验证

在 ModelSim SE-64 10.6e 实际运行完整 `-Suite All`：8 个测试平台全部通过，编译和各项日志均为 0 Error / 0 Warning。原有测试不放宽，新增计数器位宽边界用例。

| 验证 | 结果 |
| --- | --- |
| 包络 | 1905232 项检查、10 组参数通过 |
| 新增位宽边界 | 256/512/1024 点完整包络；`0xffffffff` 与 `0x80000000` 时长下的前 70000 点及误差进位、松键/重触发/复位 |
| 音量乘法 | 458757 项检查通过，包括全部 16 位输入与 7 种增益 |
| 单声部逐周期对照 | 162085 个时钟、47734 个有效样本通过，包含连续采样和随机控制 |
| Python 独立 ADSR 对照 | 相同轨迹全部匹配，14 个复位周期；完整 A/D/R 为 96/24000/5760 点 |
| 原 DDS 与 B 测试 | 原有 5 项通过；Python 核对 1024 个波表值和 4810 个 DDS 样本 |
| 语言支持 | RTL 通过 Icarus Verilog-2001 编译；高云使用 Verilog-2001 综合 |

32 位极长时长只验证了局部曲线和边界运算，没有声称完整仿真 2^32 个采样点。原 7 组参数和新增 2 的幂参数仍运行完整阶段、提前释放、重新按下、重触发及复位检查。

在仓库根目录复现功能验证（按本机安装目录调整）：

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'D:\modelsim1\win64'
python model/check_adsr.py
python model/check_dds.py
```

## 在高云现有工程复现

本次用独立临时工程调用高云命令行完成验证，未覆盖你原先 `a_dds_check` 工程中的旧报告。原 GUI 报告不会因源码已修改而自动刷新。

1. 在原工程确认顶层仍为 `voice_adsr`，六份源文件来自本仓库 `rtl`：`phase_acc.v`、`wave_lut.v`、`voice_dds.v`、`adsr_env.v`、`sample_gain.v`、`voice_adsr.v`。不要加入 `tb_*.v`。
2. 如果弹出“文件在编辑器外被修改”，选择 **Reload/重新加载**，避免用旧编辑器内容覆盖磁盘新代码。
3. 保留 `create_clock -name sys_clk -period 20.000 [get_ports {clk}]`。Synthesize → Configuration 的 Include Path 添加你自己的仓库根目录，确保能读取 `rtl/rom/sine_1024.mem`。
4. 重新运行 **Synthesize**，随后运行 **Place & Route**。确认综合没有 `Cannot open file` 或 `phase_acc ... swept` 警告。
5. 打开 **Timing Analysis Report**，确认报告日期是本次运行、时钟为 50 MHz，再核对 Setup/Hold 裕量、违例及约束。布局结果可能略有差异，以你这次报告为准。

队友整机接入时继续使用自己的板级顶层，将更新的 `adsr_env.v` 加入原有声部链路，然后对整机重新综合和布局布线。无需改变本次公开信号接口。

## 原始证据与验证范围

- [时序报告原文](reports/adsr_timing_20261003/timing.html)
- [布局布线及资源报告](reports/adsr_timing_20261003/place_route.txt)
- [综合日志](reports/adsr_timing_20261003/synthesis.log)、[布局布线日志](reports/adsr_timing_20261003/place_route.log)
- [20 ns 时钟约束](reports/adsr_timing_20261003/clock.sdc)
- [八项仿真日志](reports/adsr_timing_20261003/simulation)、[Python 实际输出](reports/adsr_timing_20261003/python_reference.txt)
- [源码、报告 SHA-256 及运行条件](reports/adsr_timing_20261003/manifest.json)

原项目文件、过程设置及执行 Tcl 作为审计快照同目录保存，包含工具产生的本机路径，不能直接作为队友可移植工程。2026-10-01 的证据保持不变，见[旧验证记录](a-adsr-validation.md)。

本次只有内部时钟约束，没有板级引脚或输入/输出延迟约束，Recovery/Removal 无可报告路径，也没有未约束路径数量统计。因此结论是 **当前默认参数的单声部模块在已约束内部路径上留出 8.265 ns Setup 裕量**；整机、其他参数配置、实际 I/O 和上板试听仍需各自验证。这些修改尚未由助手提交或推送到 GitHub。
