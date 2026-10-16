# 高云 FPGA 钢琴／摇滚电子乐器

2026-10-16：整理分支基于远程master `6120d79`，保留队友13键／双旋钮主工程，同时纳入已试听的A双音色16复音成果。**两条板级入口尚未合成一条功能链路**；使用时按接线和顶层选择工程。

| 入口 | 功能与状态 |
| --- | --- |
| [projects/piano/uart_piano.gprj](projects/piano/uart_piano.gprj) | 队友正式主工程：`piano_performance_top`，13实体键＋UART共享16声部、ADS1115音量／弯音；保持最新master源码和25信号约束 |
| [projects/music/uart_music.gprj](projects/music/uart_music.gprj) | A双音色试听：`music_uart_top`，钢琴v3／经典摇滚、16复音、UART音量／弯音；两板键、10信号约束，classic16已有用户初步可用反馈 |
| [projects/display/display_rgb.gprj](projects/display/display_rgb.gprj) | 独立RGB显示综合；屏幕引脚、PLL和触摸待落实 |
| [host/run_tone_studio.bat](host/run_tone_studio.bat) | 共用电脑工具；根据固件握手启用能力，双音色使用music入口 |
| [upstream/fpga_interaction](upstream/fpga_interaction/) | master当前C独立成果，原样保留，不与公共RTL同名模块混编 |

所有入口共用`rtl/`，各模块只有一个文件。`voice_bank_adsr`仍是13键主工程所需的波表核心；`voice_bank_music_pipe`是A的模态双音色核心，两者不能互相删除替代。原无依赖的弦乐演示／独立检查工程及其测试工具已退役。参数和来源在`model/`，测试在`verification/`，生成物写`build/`。

## 构建与验证

在仓库根运行，替换实际工具路径。A模型需要NumPy，见`model/requirements.txt`；上位机依赖见`host/README.md`。

```powershell
./verification/scripts/check_verilog.ps1 -ModelSimBin D:/modelsim1/win64
python verification/scripts/check_source_layout.py
# A双音色核心及独立定点对照
./verification/scripts/run_tests.ps1 -Suite A -ModelSimBin D:/modelsim1/win64 -Python python
# 队友13键和双旋钮主线
./verification/scripts/run_keyboard_tests.ps1 -ModelSimBin D:/modelsim1/win64
./verification/scripts/run_performance_tests.ps1 -ModelSimBin D:/modelsim1/win64
# A双音色试听位流
./projects/music/build.ps1 -Gowin C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
# 正式13键位流：使用与受控配置相符的Gowin版本
./projects/piano/build.ps1 -Gowin D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe -Python python
```

不要把两个GPRJ全部文件混到一个自建顶层。`projects/music`输出`impl/pnr/music_uart16.fs`，`projects/piano`输出`impl/pnr/piano_performance.fs`。主工程使用25信号接线，A试听沿用原10信号接线；下载采用已确认的SRAM Program，先低音量。

## 当前资料与边界

- A交接：[双音色设计](docs/music-design.md)、[双音色验证](docs/music-verification.md)、[试听指导](docs/listening-acceptance.md)。
- 正式输入主线：[设计](docs/design.md)、[接线](docs/keyboard-wiring.md)、[C输入](docs/c-input.md)、[验证](docs/verification.md)。
- 本次合并：[验证与保留范围](docs/integration-a.md)；分工与后续工作：[PLAN](PLAN.md)。

本地历史classic16包在`build/audition/music_classic16_20261014_201505/`，不随源码提交。新克隆应从对应工程构建；测试日志的历史本地路径不代表文件已上传。A只有用户初步试听反馈，正式13键／双旋钮仍以主线验证说明为准；完整外部时序、触摸和两条整机延迟仍待实测。
