# 验证入口与结果边界

2026-10-14，基于master `8277946`整合后的正式顶层为 `piano_performance_top`：13实体键/UART共享16声部，ADS1115双旋钮接入实际音频计算。当前证据统一在[性能整合摘要](../verification/evidence/performance/summary.json)，完整生成物在本机 `build/`，旧结果从Git查阅。

## 本轮实际执行

| 检查 | 本轮结果 |
| --- | --- |
| 语言 | 99份有效源码/测试严格Verilog-2001编译，无SV模式 |
| 正常回归 | All 27、UART 7、钢琴2、原13键2、PA 4、显示6、新联合5项通过 |
| 上位机 | 32项Python单测通过 |
| C独立工程 | 15 RTL＋3 Verilog控制TB严格编译；旧SV TB没有改动或作为主验证重跑 |
| 文件保护 | 基于8277946核对106份既有测试/C独立工程文件，保持不变，SHA256见摘要 |
| 音频负向检查 | 故意断开总音量或弯音连线，实际PCM/振荡器检查分别失败，正式源码不保留故障 |
| 正式综合/布局布线 | Gowin1.9.12.04、GW5AT-LV60PG484AC1/I0/B、50MHz，通过当前约束检查 |
| 资源 | Logic 19996/59904；寄存器6429/60780；BSRAM19/118；DSP67/118 |
| 报告最差余量 | setup +3.928ns；hold +0.247ns；recovery +14.858ns；removal +0.923ns；脉宽无负值 |
| 约束/配置 | 25端口指定球位；10条SDC激活；受控与实际process配置SHA256一致 |
| 位流 | `projects/piano/impl/pnr/piano_performance.fs`，未烧录 |

位流SHA256：`eb03b6ddccf5dc0b610093144f23e97e70121bf1532f446f5c3f957533b4b63d`。16个pROM是独立声部音频表，另一个pROM是旋钮频率比例表，不当作第17声部。DSP/逻辑增加来自16路并行合成、弯音和ADC前端。

弯音乘法增加一级系统时钟流水线，正式请求R0→DDS/包络R1→混音R4→总音量R5→B缓存R6；提前32/33拍准备，仍满足数字帧截止时间。原四路接口配置保持R4缓存，原tb判据没有放宽。旧配置的额外未接控制端口有仿真兼容告警；正式16路新增联合测试无端口告警。

## 新联合测试测了什么

- `tb_performance_bank`：16路逐路实际非零样本；C4在0.2秒样本窗的正向过零次数为原音53、升2半音59、降2半音47、回中53；检查数字增益/静音、尾音弯音、真实完成代次、连续请求控制对齐及复位。
- `tb_performance_system`：实体/UART同音分离、13键＋电脑填满16路、17音抢占、延音、八度锁存、实际末级增益、数字串行输出、实体队列故障只清本地、PANIC跳过延音只清PC。
- `tb_performance_adc`：位级I2C从机模型→ADC→正式16路顶层，检验PCM静音、振荡器弯音、掉线保持、恢复和复位；为了仿真速度缩短转换等待并关闭前端平滑，不能用于宣称默认旋钮响应。
- `tb_performance_control`：held-gate重触发代次、过期完成拒绝、延音/按住状态分离、来源清理、八度快照、背压、溢出锁存与复位。
- `tb_performance_latency`：正式顶层、真实50MHz/48kHz、2ms消抖和原钢琴包络，13音高/不同相位的新起音；稳定数字接点至完整左声道数字字最大观测 **2.030640ms**。

此延迟没有计入机械抖动、DAC/功放模拟响应、触摸或旋钮采集，不是整机≤5ms/≤10ms或全工况最坏上界证明。所有声部非零检查只在有效发声窗口计数；钢琴自然衰减到零后占用状态不当作可闻声部。

## 复现命令

在仓库根运行，工具路径按实际安装修改：

```powershell
./verification/scripts/check_verilog.ps1
./verification/scripts/run_tests.ps1 -Suite All -ModelSimBin C:/Library/modelsim/win64
./verification/scripts/run_uart_tests.ps1
./verification/scripts/run_piano_tests.ps1
./verification/scripts/run_pa_tests.ps1
./verification/scripts/run_keyboard_tests.ps1 -ModelSimBin C:/Library/modelsim/win64
./verification/scripts/run_display_tests.ps1
./verification/scripts/check_c_rtl.ps1
./verification/scripts/run_performance_tests.ps1
./verification/scripts/run_performance_tests.ps1 -Mutation Volume -Tests tb_performance_system
./verification/scripts/run_performance_tests.ps1 -Mutation Bend -Tests tb_performance_adc
& .venv-studio/Scripts/python.exe -m unittest discover -s host -p 'test_*.py'
$projectPython='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
./projects/piano/build.ps1 -EvidenceDirectory build/performance -Python $projectPython
& $projectPython -X utf8 verification/scripts/summarize_performance.py
```

## 尚未签核的事项

PR1014系统时钟通用路由告警、DAC的DIN/WS相对BCK完整外部时序、实物声音及整机最坏延迟尚待闭合；正余量只表示当前约束中的报告结果。SDA经两级同步，输入例外只切异步外部路径，未豁免同步器级间路径；SCL是同域使能输出，无新增内部逻辑时钟。

ADC默认128SPS、每通道固定等待10ms，加16对预热/IIR/限速，旋钮可能数百毫秒才稳定，本轮未优化或实测这一段。延音/八度仅内部接口，正式板级默认关闭/中档。触摸和显示主顶层尚未接入，钢琴真实感未改善、未验收。

较早的13键阶段与清理阶段记录对应Git `b59f8ee`、`0406c60`、`f513622`；不混作本轮证据。C独立快照继续保留，旧缓存回收位置见本机 `build/cleanup/cache-location.txt`。


## 2026-10-16 A双音色整理分支合入说明

已核对远程master基线`6120d79`。正式13实体键／ADS1115双旋钮入口仍为`projects/piano/uart_piano.gprj`、`piano_performance_top`，保留该基线的RTL、约束、配置和C独立工程。

A当前成果为钢琴v3／经典摇滚、共享16复音、UART总音量／±2半音弯音，独立试听入口`projects/music/uart_music.gprj`、`music_uart_top`，沿用原两板键和十信号约束。两工程共用公共RTL目录，不复制整个A/B/C工程。不能把A试听的音色／控制能力宣称已接入13键／ADC主工程，也不能给A入口使用25信号主工程约束。

此前本地清理按`0406c60`删除的部分模块，已成为最新13键主工程的实际依赖，因此保留其唯一公共实现与必要测试；无依赖的旧弦乐演示、独立检查工程及专用工具继续退役。C原始工程和新增实体键／控制测试随master保留，不改写队友TB。

A接口见[双音色设计](music-design.md)，结果见[双音色验证](music-verification.md)和[合并验证](integration-a.md)。下一步才是把A音色核心接入正式13键／双旋钮通路并重新做资源、时序和板级验收。原classic16位流仍只适用于此前两键试听接线。
