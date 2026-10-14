# 高云 FPGA 电子钢琴

2026-10-14：**13实体键与UART共享16声部，两个旋钮实际控制总音量和全局±2半音弯音**。保留板载C4/E4别名，音色仍为当前钢琴近似。
主顶层为 `piano_performance_top`，25个端口有约束，接线见[接线与运行](docs/keyboard-wiring.md)。CPU引脚GPIO复用保持开启。
验证记录见[验证说明](docs/verification.md)。本轮尚未下载或实测整机延迟；C的队列、来源清理、起音/完成代次已适配到实际主链路。
延音/八度内部控制接口已接通，板级暂固定延音关闭、中音区；触摸和显示主顶层接入仍待完成。第二音色为吉他，屏幕型号与触摸驱动未落实。

## 工程入口

| 入口 | 用途 |
| --- | --- |
| [projects/piano/uart_piano.gprj](projects/piano/uart_piano.gprj) | **主工程**，顶层 `piano_performance_top`，16声部＋旋钮 |
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

旧 `adsr_voice_bank.v` 与 `demo_voice_bank.v` 已删除，**当前钢琴只用 `voice_bank_adsr.v`**。`adsr_env.v` 负责包络，`voice_timbre_adsr.v` 负责一个声部，`voice_bank_adsr.v` 参数化组织声部，正式配置16路，默认4路兼容原验证；职责不同，不是三份旧版本。新吉他/弦乐算法暂作独立开发。

主工程与C工程仍有少量同名模块：它们是两个当前开发入口的不同接口实现，不能混编或直接互相覆盖；用户选择保留C独立工程。本次在原路径刷新10月14日已发布C成果，保留队友历史SV测试的接口版本；三份新增控制测试整理为严格Verilog .v。

## 构建与上板

本机工具：Gowin `D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe`；ModelSim10.6e `C:/Library/modelsim/win64`。换电脑请覆盖脚本的工具路径参数。

```powershell
./verification/scripts/check_verilog.ps1
./verification/scripts/run_performance_tests.ps1
./projects/piano/build.ps1 -EvidenceDirectory build/performance -Python C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
```

器件为GW5AT-LV60PG484AC1/I0、Version B，引脚依据NEO Dock31004 Rev1.4。主工程引用[板级约束](boards/tang_mega_60k_31004/)，新增13路PMOD按钮输入。位流在 `projects/piano/impl/pnr/piano_performance.fs`，身份以本次 `build/performance/artifact.txt` 为准。

上板先用已确认的SRAM Program、低音量耳机测试，不自动写Flash。预期KEY1/KEY2能发声；按住时约1.202秒衰减至零，提前松键约180ms收尾。PC与板键共享16声部，满载优先抢占最老松键尾音，其次最老按住音；串口默认115200/8N1。旋钮0为音量，旋钮1为全局弯音；ADC未就绪沿用原音量/原音高，掉线保持最后有效值。PT8211-S使用LSBJ右对齐格式，不因模块名 `i2s_tx` 就称为标准Philips I2S，赛题接口口径尚需确认。

显示工程没有PLL、CST或可下载位流，不能直接按主工程方式下载。显示刷新与触摸采集是两条不同通路；已有琴键图形不是触摸驱动。双入口均以整机≤10ms为基础目标、≤5ms优先争取，分别验证，不用实体键数据替触摸达标。

## 当前文档

- [PLAN.md](PLAN.md)：目标、A/B/C分工、赛题要求及未完成项。
- [docs/design.md](docs/design.md)：当前音频通路、位宽/有效时刻、音色依据。
- [docs/display-rgb.md](docs/display-rgb.md)：显示接口与时序。
- [docs/keyboard-assembly.md](docs/keyboard-assembly.md)：13键装配。
- [docs/verification.md](docs/verification.md)：验证命令、结果边界及Git历史入口。

旧代码、旧报告、旧设计计划不再在当前目录复制保存；清理前完整版本为Git提交 `f513622`。原始PDF/用户资料、字体许可证和C最新工程保留。清理本身不增加功能，也不证明实物延迟达标。
