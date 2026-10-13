# 目录入口与迁移记录

2026-10-13按用户批准的B部分低延迟计划重整。功能检查点`4482f58`在目录迁移之前，可将功能与路径调整分别审阅。

| 旧入口 | 当前入口 | 用途 |
| --- | --- | --- |
| `fpga_project/uart_piano` | `projects/piano` | 当前主钢琴工程 |
| `fpga_project/uart_basic` | `projects/uart_basic` | UART固定正弦基线 |
| `fpga_project/display_rgb` | `projects/display` | 中文显示独立综合，未选屏/未约束引脚 |
| 根`fpga_project`旧两键工程 | `projects/examples/adsr` | ADSR/渐变普通及自动演示 |
| `fpga_project/instruments_board` | `projects/examples/instruments_board` | 双乐器独立试听 |
| 两个`*_check` | `projects/checks` | 已有独立实现检查 |
| 四个`fpga_a/b/interaction/ab_sim` | `upstream/`下同名目录 | 队友原字节快照；不改其tb或脚本 |
| `sim`、`tb`和验证脚本 | `verification/tb`、`verification/scripts` | 主工程严格Verilog-2001验证 |
| `fpga_music_tool` | `host` | 上位机与原预设 |
| 已跟踪`results` | `docs/reports/legacy` | 342份历史证据，原字节保留 |
| 根`doc` | `docs/history/legacy-doc` | 历史文档原文 |
| 未提交旧日志/工作库 | `build/retained-before-migration` | 可恢复保留，不冒充新证据 |

公共RTL分为`audio`音频输出、`display`显示、`synth`合成、`control`输入与事件、`common`公共逻辑、`top`顶层和`rom`波表。分类不改变模块名、接口或职责。

迁移前逐文件记录2636个路径/大小/SHA256，实际移动1964个文件。所有目标在路径文本改写之前全量核对通过，删除文件数为0。四个队友快照共78文件的路径集合和字节均一致。必要Gowin process配置保留，不把它们当缓存。

原清单和移动日志见[迁移证据](reports/b-review-20261013/migration/)。清单是迁移当时的快照：活动脚本、工程引用和当前说明随后需要修正路径，不能要求这些可编辑文件仍匹配迁前哈希；`preserveBytes=true`的历史报告、ROM和队友快照继续逐字节校验。

`projects/legacy`仅保全原工程及原字节，不作为重建成功证明。部分历史GPRJ的XML声明为`version="1"`，审计时只在内存兼容读取，没有改原文件。不要把它们与本次已验证活动工程混为一谈。

旧报告中的旧路径、提交、时间和哈希不批量替换。历史结果只对其记录版本负责；本轮结果以新报告和构建输入清单为准。新运行的日志、波形、工作库集中到`build/`；Gowin邻近工程的`impl/`是工具所需例外，生成位流不自动上传。

## 验证入口

在仓库根执行（本机ModelSim为`C:/Library/modelsim/win64`）：

```powershell
./verification/scripts/check_verilog.ps1
./verification/scripts/run_modelsim.ps1 -Mode run
./verification/scripts/run_tests.ps1 -Suite All -ModelSimBin C:/Library/modelsim/win64
./verification/scripts/run_uart_tests.ps1
./verification/scripts/run_piano_tests.ps1
./verification/scripts/run_display_tests.ps1
./verification/scripts/run_pa_tests.ps1
./verification/scripts/run_latency_tests.ps1 -ExtraTests tb_audio_boundaries,tb_audio_display_isolation
./verification/scripts/check_audio_parameters.ps1
./projects/piano/build.ps1
./projects/uart_basic/build.ps1 -Mode Uart
./projects/display/build.ps1
./projects/check_implementation.ps1 -Group All
```

迁后已实际运行严格编译、上述功能回归、默认入口compile/run、主钢琴干净复建、UART实现和显示综合；实现矩阵的7项按Examples/Checks/Instruments三组分别执行通过，不是宣称另跑了一次All。结果见[完成记录](reports/b-review-20261013/completion.md)。主工程只用Verilog，不把未运行的队友SystemVerilog测试说成通过。实物下载、完整外部时序和整机延迟仍未验收。

最终2199个原字节保留项SHA及四套快照集合再次核对通过。迁移脚本是一次性历史操作的清单/执行器，不应在新目录布局下重新生成旧布局迁移计划；核对原清单请使用`-VerifyManifest`和`-ImmutableOnly`。
