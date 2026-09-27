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

`-Suite A` 仅运行 A，`-Suite B` 仅运行 B。也可以通过 `MODELSIM_BIN` 环境变量指定工具目录。
模型使用 Python 3 标准库；仿真本身不依赖 Python。综合、上板及 A+B 联合仿真仍待完成。
## 仿真（原有练习入口）

当前 Windows 环境使用 ModelSim SE-64 10.6e。运行前请根据本机安装位置检查 [docs/vscode-verilog-setup.md](docs/vscode-verilog-setup.md) 和 `run_modelsim.ps1` 中的工具路径。

```powershell
.\run_modelsim.ps1 -Mode compile
.\run_modelsim.ps1 -Mode run
```

仿真数据库、波形和临时工作库已加入 `.gitignore`，源码和测试平台仍会保留在仓库中。

## 真实性边界

代码已写、仿真通过、综合通过、时序通过和实物验证是不同状态。本仓库不会把其中一个状态写成全部完成；每项结论都应附对应的工具输出或实测证据。
