# FPGA 多音色电子乐器

高云 FPGA 题二项目：使用 FPGA HDL 实时生成多音色、多复音音频，并通过 I2S 输出到音频 DAC。

## 项目目标

- 从单音闭环开始，逐步完成至少四个独立声部；
- 支持音符选择、触发和力度等独立演奏维度；
- 在 FPGA 内完成波形、ADSR 包络和多声部混音；
- 通过 I2S 输出数字音频；
- 准备至少两种可辨别的合成音色；
- 用仿真、综合、上板和实测数据分别记录验证结果。

## 分工（暂定）

- **A：波形与合成**：DDS、波表、ADSR、声部增益、混音和饱和处理；
- **B：音频输出与集成**：采样节拍、I2S、时钟/复位、顶层工程和时序；
- **C：交互与声部管理**：输入同步、消抖、压力采集、事件编码和四声部分配。


## 目录

```text
rtl/       自研 Verilog RTL 模块
sim/       测试平台和仿真脚本
docs/      工具配置、接口说明和项目资料
results/   可复现的测试结果（生成文件不提交）
PLAN.md    学习、开发、风险和验收计划
AGENTS.md  项目协作约定
```

## A 模块：单声部 DDS

A 的相位累加器、正弦波 ROM 和单声部 DDS 已加入 `rtl/`，测试位于 `sim/`。
接口、波表位置及交互式波形操作见 [A 模块说明](docs/a-dds.md)，实测仿真结论见 [验证记录](docs/a-dds-validation.md)。

新的参数化批量入口支持 A 与现有 B 测试，替代下面旧练习入口用于本阶段验证：

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin '你的ModelSim安装目录\win64'
python model/check_dds.py
```

`-Suite A` 运行 A 的六项测试（含 ADSR），`-Suite ADSR` 仅运行新增三项，`-Suite B` 仅运行 B。也可以通过 `MODELSIM_BIN` 环境变量指定工具目录。
模型使用 Python 3 标准库；仿真本身不依赖 Python。旧 DDS 综合和旧版发声已有用户反馈，正式报告待补；ADSR v2 已完成单模块综合、布局布线及 50 MHz 下内部时序检查；整机接口、上板和试听仍待验证。
## A 模块：ADSR 包络

`adsr_env`、`sample_gain` 和 `voice_adsr` 已升级为按采样点数控制的单声部包络，并补充中文注释。默认 48 kHz 下起音 2 ms、衰减 500 ms、保持约 10% 幅度、从当前非零幅度释放 120 ms。接口、默认参数、ModelSim 图形操作及本次验证记录见 [ADSR 说明](docs/a-adsr.md)。

```powershell
.\sim\run_tests.ps1 -Suite ADSR -ModelSimBin '你的ModelSim安装目录\win64'
python model/check_adsr.py
```

2026-10-03 优化包络关键路径后，8 项 A/B 测试全部通过，包络覆盖 10 组参数、1905232 项检查，单声部的 47734 个样本与 RTL 测试平台、Python 模型一致。新声部比原 DDS 多一拍 `clk` 延迟；松开后仍须继续采样以完成释放。本次时序优化保持接口、参数和输出延迟。旧 `ATTACK_STEP/DECAY_STEP/RELEASE_STEP` 参数已在 v2 换为 `ATTACK_SAMPLES/DECAY_SAMPLES/RELEASE_SAMPLES`，旧实例仍需迁移。相同器件和 50 MHz 约束下，高云重新综合、布局布线后 Setup 裕量从 +0.352 ns 提高到 **+8.265 ns**，Hold +0.247 ns，违例均为 0；整机约束与上板试听待验证。最新原始报告、改动原因与复现步骤见 [时序优化记录](docs/a-adsr-timing-20261003.md)，10 月 1 日记录保留在 [旧验证与交接记录](docs/a-adsr-validation.md)。

## 仿真（原有练习入口）

当前 Windows 环境使用 ModelSim SE-64 10.6e。运行前请根据本机安装位置检查 [docs/vscode-verilog-setup.md](docs/vscode-verilog-setup.md) 和 `run_modelsim.ps1` 中的工具路径。

```powershell
.\run_modelsim.ps1 -Mode compile
.\run_modelsim.ps1 -Mode run
```

仿真数据库、波形和临时工作库已加入 `.gitignore`，源码和测试平台仍会保留在仓库中。

## 真实性边界

代码已写、仿真通过、综合通过、时序通过和实物验证是不同状态。本仓库不会把其中一个状态写成全部完成；每项结论都应附对应的工具输出或实测证据。
