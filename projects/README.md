# 高云EDA工程入口

2026-10-13目录重整。主试听入口是钢琴工程，其他活动模式单独保留；历史工程在 `legacy/`，不混入当前构建。路径调整不等于已经重新综合或上板，请以本轮构建记录和位流哈希为准。

| 工程 | 打开文件／构建入口 | 用途 |
| --- | --- | --- |
| [钢琴](piano/README.md) | `piano/uart_piano.gprj`、`piano/build.ps1` | 当前四声部UART／两板键钢琴近似 |
| [UART正弦](uart_basic/README.md) | `uart_basic/uart_basic.gprj`、`uart_basic/build.ps1 -Mode Uart` | 基础演奏回退 |
| [板键演示](examples/adsr/README.md) | `examples/adsr/fpga_project.gprj`、四个build Tcl | ADSR普通／自动、旧渐变普通／自动 |
| 双音色试听 | `examples/instruments_board/instruments_board.gprj`、`run.tcl` | 已有独立音色工程，不代表吉他已接主钢琴 |
| 核心检查 | `checks/poly_adsr_check/`、`checks/instruments_check/`的`run.tcl` | 寄存器外壳下综合布局布线，不可当板级文件下载 |
| [中文RGB显示](display/README.md) | `display/display_rgb.gprj`、`display/build.ps1` | 仅综合，无屏幕引脚／PLL／下载文件 |

## 从仓库根构建

```powershell
./projects/piano/build.ps1
./projects/uart_basic/build.ps1 -Mode Uart
./projects/display/build.ps1
./projects/check_implementation.ps1 -Group All
$gowin = 'D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe'
& $gowin ./projects/examples/adsr/build_adsr_demo.tcl
& $gowin ./projects/examples/adsr/build_adsr_auto_demo.tcl
& $gowin ./projects/examples/adsr/build_demo.tcl
& $gowin ./projects/examples/adsr/build_auto_demo.tcl
& $gowin ./projects/examples/instruments_board/run.tcl
& $gowin ./projects/checks/poly_adsr_check/run.tcl
& $gowin ./projects/checks/instruments_check/run.tcl
```

四个ADSR／渐变模式共用一个GPRJ和impl，不能并行构建；最后一次脚本决定GUI当前顶层。其他电脑替换Gowin安装路径。脚本均只构建，不连接或烧录板卡。

推荐用`check_implementation.ps1`一次串行检查后面7种模式，支持`-Group Examples/Checks/Instruments/All`、`-Gowin`和`-EvidenceDirectory`，默认保存`build/implementation-matrix`。它保全并恢复已有ADSR impl配置，检查源码哈希、工具成功标记和现有时序约束，不替代板级完整签核。本轮已分别执行三个分组，见[迁后证据](../docs/reports/b-review-20261013/completion.md)。

三个PowerShell入口支持`-Gowin`和`-EvidenceDirectory`；默认日志/清单进入`build/piano`、`build/uart_basic`和`build/display/synthesis`。Gowin生成的`impl/`必须在工程旁边，作为忽略的工具输出例外。各活动工程根的`process_config.json`是必要输入，不是缓存；Tcl在打开工程前恢复它。ADSR已有的受控impl配置仍保留，构建脚本以根配置为干净构建来源。

`./projects/uart_basic/build.ps1 -Mode Legacy`另行在证据目录创建当前ADSR工程的隔离复制品，兼容原检查入口，不会构建或改写`projects/legacy/`中的历史文件。

## 硬件与证据边界

板级活动工程沿用NEO Dock31004／GW5AT-LV60PG484AC1/I0、Version B与已核实约束。旧报告、旧哈希和原路径记录仍有追溯意义，但不证明当前工作区的实现结果。PR1014、完整DAC外部时序、实体13键／旋钮、屏幕选型与整机模拟输出延迟仍需单独验证。

历史单音、旧约束、C交互与JESD示例在`legacy/`原字节保留，不重新构建；其中自动分配引脚的旧`fpga_project.fs`不得作为当前上板候选。
