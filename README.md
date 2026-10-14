# 高云 FPGA 电子钢琴

2026-10-14 本地接入 **13个独立低有效琴键，C4～C5，四声部固定钢琴近似音色**；保留板载C4/E4测试键与UART电脑演奏。
主顶层为 `piano_13key_top`，接线见 [13键接线与运行](docs/keyboard-wiring.md)，23个端口均有约束，CPU引脚GPIO复用已开启。
18项相关回归和87文件严格Verilog编译通过，50MHz布局布线时序通过；接线、下载和整机模拟延迟仍待实物验证。本次C阶段成果整理到 master，主钢琴与独立C的入口见下表及[C输入说明](docs/c-input.md)。
13个屏幕虚拟琴键、旋钮、延音/八度和16声部钢琴合成仍需对接；第二音色为吉他，屏幕型号与触摸驱动未落实。

## 工程入口

| 入口 | 用途 |
| --- | --- |
| [projects/piano/uart_piano.gprj](projects/piano/uart_piano.gprj) | **主工程**，顶层 `piano_13key_top` |
| [projects/display/display_rgb.gprj](projects/display/display_rgb.gprj) | 800×480中文RGB显示核心，仅独立综合；触摸输入待新增，未定屏幕/引脚 |
| [projects/examples/instruments_board](projects/examples/instruments_board/) | A的新吉他/弦乐试听，尚未合入主钢琴，不是钢琴旧版本 |
| [projects/checks](projects/checks/) | 当前合成核心的独立时序检查，不用于下载 |
| [upstream/fpga_interaction](upstream/fpga_interaction/) | C最新独立工程：八度、延音、起音序号、队列故障清理；与主钢琴接口适配待完成 |
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

主工程与C工程仍有少量同名模块：它们是两个当前开发入口的不同接口实现，不能混编或直接互相覆盖；用户选择保留C独立工程。本次在原路径刷新10月14日已发布C成果，保留队友历史SV测试的接口版本；三份新增控制测试整理为严格Verilog .v。

## 构建与上板

本机工具：Gowin `D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe`；ModelSim `D:/Modelsim/win64`。换电脑请覆盖脚本的工具路径参数。

```powershell
./verification/scripts/verify_keyboard.ps1 -ModelSimBin D:/Modelsim/win64
./projects/piano/build.ps1 -Gowin D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
```

器件为GW5AT-LV60PG484AC1/I0、Version B，引脚依据NEO Dock31004 Rev1.4。主工程引用[板级约束](boards/tang_mega_60k_31004/)，新增13路PMOD按钮输入。位流在 `projects/piano/impl/pnr/piano_13key.fs`，身份以本次 `build/piano/artifact.txt` 为准。

上板先用已确认的SRAM Program、低音量耳机测试，不自动写Flash。预期KEY1/KEY2能发声；按住时约1.202秒衰减至零，提前松键约180ms收尾。PC与板键共享四声部，满载会抢占；串口默认115200/8N1。PT8211-S使用LSBJ右对齐格式，不因模块名 `i2s_tx` 就称为标准Philips I2S，赛题接口口径尚需确认。

显示工程没有PLL、CST或可下载位流，不能直接按主工程方式下载。显示刷新与触摸采集是两条不同通路；已有琴键图形不是触摸驱动。双入口均以整机≤10ms为基础目标、≤5ms优先争取，分别验证，不用实体键数据替触摸达标。

## 当前文档

- [PLAN.md](PLAN.md)：目标、A/B/C分工、赛题要求及未完成项。
- [docs/design.md](docs/design.md)：当前音频通路、位宽/有效时刻、音色依据。
- [docs/display-rgb.md](docs/display-rgb.md)：显示接口与时序。
- [docs/keyboard-assembly.md](docs/keyboard-assembly.md)：13键装配。
- [docs/verification.md](docs/verification.md)：验证命令、结果边界及Git历史入口。

旧代码、旧报告、旧设计计划不再在当前目录复制保存；清理前完整版本为Git提交 `f513622`。原始PDF/用户资料、字体许可证和C最新工程保留。清理本身不增加功能，也不证明实物延迟达标。
