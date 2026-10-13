# 高云 FPGA 电子钢琴

当前可运行的是 **四声部固定钢琴近似音色**：KEY1=C4、KEY2=E4，KEY0复位；支持UART电脑演奏。正式目标为13实体琴键＋两个旋钮＋纯显示屏、16复音，尚未全部接入。第二音色选吉他，不做触摸演奏。

## 工程入口

| 入口 | 用途 |
| --- | --- |
| [projects/piano/uart_piano.gprj](projects/piano/uart_piano.gprj) | **主工程**，顶层 `instrument_uart_piano_top` |
| [projects/display/display_rgb.gprj](projects/display/display_rgb.gprj) | 800×480中文RGB显示，仅独立综合，未定屏幕/引脚 |
| [projects/examples/instruments_board](projects/examples/instruments_board/) | A的新吉他/弦乐试听，尚未合入主钢琴，不是钢琴旧版本 |
| [projects/checks](projects/checks/) | 当前合成核心的独立时序检查，不用于下载 |
| [upstream/fpga_interaction](upstream/fpga_interaction/) | 用户明确保留的C最新独立工程：按键、旋钮、声部分配 |
| [host/README.md](host/README.md) | 电脑音色设计台与串口演奏 |

```text
rtl/                 当前公共源码：audio、control、synth、display、top、rom
projects/            当前高云工程及必要process配置
boards/              当前主钢琴的引脚与时序约束
verification/        当前功能的Verilog测试与运行脚本
upstream/            仅C正在开发的独立工程，不与主工程混编
host/、model/        上位机、参考模型及波表生成/检查
docs/                必要说明、原始赛题资料与许可证
build/               本次生成的日志和波形，不提交
```

旧 `adsr_voice_bank.v` 与 `demo_voice_bank.v` 已删除，**当前钢琴只用 `voice_bank_adsr.v`**。`adsr_env.v` 负责包络，`voice_timbre_adsr.v` 负责一个声部，`voice_bank_adsr.v` 组织四个声部；职责不同，不是三份旧版本。新吉他/弦乐算法暂作独立开发。

主工程与C工程仍有少量同名模块：它们是两个当前开发入口的不同接口实现，不能混编或直接互相覆盖；用户选择保留C独立工程。清理没有改C的RTL、TB或脚本。

## 构建与上板

本机工具：Gowin `D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe`；ModelSim `C:/Library/modelsim/win64`。换电脑请覆盖脚本的工具路径参数。

```powershell
./verification/scripts/check_verilog.ps1
./verification/scripts/run_piano_tests.ps1
./projects/piano/build.ps1
```

器件为GW5AT-LV60PG484AC1/I0、Version B，现有引脚依据NEO Dock31004 Rev1.4。主工程引用[板级约束](boards/tang_mega_60k_31004/)，清理没有改变引脚/电压。位流在 `projects/piano/impl/pnr/instrument_uart_piano.fs`，身份以本次 `build/piano/artifact.txt` 为准，不能拿历史哈希替代。

上板先用已确认的SRAM Program、低音量耳机测试，不自动写Flash。预期KEY1/KEY2能发声；按住时约1.202秒衰减至零，提前松键约180ms收尾。PC与板键共享四声部，满载会抢占；串口默认115200/8N1。PT8211-S使用LSBJ右对齐格式，不因模块名 `i2s_tx` 就称为标准Philips I2S，赛题接口口径尚需确认。

显示工程没有PLL、CST或可下载位流，不能直接按主工程方式下载。

## 当前文档

- [PLAN.md](PLAN.md)：目标、A/B/C分工、赛题要求及未完成项。
- [docs/design.md](docs/design.md)：当前音频通路、位宽/有效时刻、音色依据。
- [docs/display-rgb.md](docs/display-rgb.md)：显示接口与时序。
- [docs/keyboard-assembly.md](docs/keyboard-assembly.md)：13键装配。
- [docs/verification.md](docs/verification.md)：验证命令、结果边界及Git历史入口。

旧代码、旧报告、旧设计计划不再在当前目录复制保存；清理前完整版本为Git提交 `f513622`。原始PDF/用户资料、字体许可证和C最新工程保留。清理本身不增加功能，也不证明实物延迟达标。
