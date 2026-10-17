# 当前验证与验收边界

2026-10-17，复核并修正Opus的包络重定时与界面证据对应关系。正式入口继续采用队友master `e18160e` 的钢琴v3／经典摇滚电吉他模态核心、13键／双旋钮、双模式中文HDMI画面及八白键连续接线。下面只报告当前实现；旧波表版本的资源、时序和位流不作为下载依据。

**当前结论：RTL与数字集成验证、两个入口的综合／布局布线及现有约束检查通过；新位流尚未下载，实物验收和完整外部时序仍未完成。** 工作区存在未提交改动，不能只用Git HEAD表示受测内容；以[当前审计摘要](../verification/evidence/final/summary.json)及其源码／约束／工具输入哈希为准。

## 当前实现与位流

器件GW5AT-LV60PG484AC1/I0、Version B，实物NEO Dock31005＋60K核心板；Gowin1.9.12.04、ModelSim10.6e。系统50MHz／音频48kHz／16位；HDMI像素49MHz、串行245MHz。正式16声部R923样本有效、R924缓存，提前60个半位边沿请求，至少976拍准备窗口。

| 指标 | 带屏主工程 | 无屏入口 |
|---|---:|---:|
| Logic／59904 | 19835 | 16127 |
| Register／60780 | 7716 | 7110 |
| BSRAM／118 | 94 | 80 |
| DSP／118 | 13.5 | 13 |
| Setup最差余量/ns | +1.021 | +0.744 |
| Hold最差余量/ns | +0.203 | +0.146 |
| Recovery最差余量/ns | +0.834 | +14.893 |
| Removal最差余量/ns | +0.143 | +1.220 |
| 最小脉宽余量/ns | +5.803 | +6.809 |
| 位置约束端口 | 34 | 25 |
| 生效SDC条数 | 17 | 10 |

DSP的13.5是Gowin半块计数，检查器保留小数，没有改变时序门槛。当前最薄Setup为0.744ns（无屏）、1.021ns（带屏），最薄Hold为0.146ns、Removal为0.143ns；仍需结合约束覆盖和实物条件理解，不称时序宽裕或全面签核。

本次保留2bit覆盖度字模与原生48px标题，但删除会读取旧预设/旧幅度的包络缓存，改为两预设首步幅度并行计算后选择。相对Opus未修正版本：带屏Logic 18956→19835、Register 8292→7716；无屏Logic 15433→16127、Register 7686→7110。带屏BSRAM保持94/118（约80%，余24块），DSP保持13.5；无屏BSRAM80、DSP13。逻辑增加、寄存器减少是此次正确性修复和并行候选的交换，不拿错误版本较高的时序余量作为可用收益，也不把不同布局结果直接归因于某一个RTL表达式。

| 下载场景 | 唯一位流 | SHA256 |
|---|---|---|
| 7寸HDMI屏＋实体键＋旋钮 | `projects/hdmi/impl/pnr/piano_hdmi.fs` | `ff31df445be9e63de55c86415da87be6336f6a5f097c5c8b9d8f80d063aa1052` |
| 不接显示屏 | `projects/piano/impl/pnr/piano_performance.fs` | `615a7788cb992c567e55b1ea779e8d9b100806d9010cf387cf647717f281eff3` |

本轮两入口均重新综合／布局布线。构建分别绑定72／52份输入，报告、配置、源文件和位流身份由审计再次核对。原SDC、时序例外、process及HDMI十二个复位原语位置约束保持；HDMI检查器核对实际落点，并保留原0.100ns复位优化门槛。

接线必须用[新表](keyboard-wiring.md)：八键K1～K8全白键接J13-1..8，五黑键接9/10/13/14/15，ADC仍16/17。按用户正面照片，网口左／金手指下时，1脚右上、2脚右下，从右向左增加。11脚为5V，不接这些3.3V信号或模块电源。不能混用旧半音排列的位流。

## 正式数字验证

149个发布RTL／TB以`-vlog01compat -pedanticerrors`编译，未使用SV模式；临时UI打印探针移入build/review-opus，不作为发布输入。原队友TB／黄金数据、C独立工程和受保护时序／配置共145份文件，与本轮起点逐字节核对不变；34份从A最新版导入的文件同样保持原内容。新增适配与显示测试独立存放，不修改原测试迎合结果。

| 当前测试 | 实际检查与结果 |
|---|---|
| tb_final_modal_adapter | 4436样本与未经修改的A核心逐点一致；含两预设、增益/弯音、忙中换代次、16位代次回绕、尾音、overrun及复位 |
| tb_final_performance | 正式无屏入口16个非零声部，真实I2C节拍/转换等待到新核心的静音/弯音/故障保持/恢复；来源/抢占/模式/尾音；20642个DAC串行字精确匹配 |
| tb_performance_latency | 原测试不改，正式新入口13个音符起音；逻辑输入到完整非零左DAC字最大观测2.070600ms |
| tb_final_wave_envelope | 256列逐列min/max、正负满幅/尖峰、帧原子换页、×1～256自动倍率、弱音慢恢复、静音及复位 |
| tb_final_display_frame | UI=0兼容帧；CVT/中文标题逐像素、帧中切模式、波形1929像素/49像素可见高度、285个吉他标记像素、钢琴旧音不混入指板 |
| tb_final_display_ui | 新1024×600界面的真实模态帧：CVT帧长与消隐、1841400个有效像素与绘制器逐像素一致、标题覆盖度与柔边、持键高亮；与旧兼容绘制器共用同一模块 |
| tb_final_hdmi_isolation | 正式有屏／无屏16声部下UART及音频引脚逐拍一致；HPD/PLL失锁/像素停钟/复位、旋钮故障，369个音频样本与19次显示副本丢弃 |
| tb_final_env_alignment | 独立整数参考139069次对照；接受拍换预设、连续采样、零/一拍/非二次幂/65537以上时长、释放与复位；不使用同一个RTL实例作黄金参考 |

2.070600ms仅是上述数字条件下的最大观测值：以逻辑按键拉低为起点、完整DAC串行字首次非零为终点，排除了机械抖动和DAC／模拟／音箱响应；不是整机模拟延迟，也不穷举所有最坏工况。新核心的18.48µs计算时间同样不能代替整机测量。

A原始7组测试全部重跑通过，含4／16声部各11400点、7500帧控制、来源／抢占／恢复与箱体尾音。独立Python定点模型再次对照11400点输出、状态、4／16声部和原黄金摘要；没有用参考软件替代FPGA发声。

通用／兼容回归已执行：All27、基础显示6、算术／字库／布局3、原性能核心3、原ADC／R7双音色／HDMI隔离3、UART7与容量2。原R7测试通过build内显式兼容参数包装运行，它们只证明兼容配置，不当作新R924入口证据。四路HDMI原语位序、TMDS编码及17次启动／恢复测试通过；恢复后损坏红通道的故障被拒绝。电脑端53项及双音色识别4项通过，均不打开真实串口。

本轮重新执行的负向对照均被预期检查器拒绝：包络首步清零、预设取反接错、忙时旧release_done泄漏、波形max变min；引脚检查另拒绝错球位、错电压及错实际报告，HDMI检查另拒绝错误布局和低于原门槛的正余量。恢复后红通道损坏也被拒绝。故障副本只在build，不进入工程。

当前两张预览来自`tb_final_display_ui`的UI=1真实输出，每张614400个RGB像素；审计验证PNG解码内容逐字节等于`*_ui_frame.hex`，并检查与独立保留的UI=0转储身份不同，禁止拷贝覆盖旧转储迎合审计：
[钢琴](display-piano.png)、[吉他](display-guitar.png)。显示自动倍率不会改变音频增益；电平条使用未经显示放大的峰值，红色仅表示接近满幅。

## 重现命令

```powershell
./verification/scripts/check_verilog.ps1
python verification/scripts/run_final_tests.py tb_final_env_alignment tb_final_modal_adapter tb_final_performance tb_performance_latency tb_final_wave_envelope tb_final_display_frame tb_final_display_ui tb_final_hdmi_isolation
python verification/scripts/run_final_tests.py tb_final_env_alignment --mutation Env
python verification/scripts/run_final_tests.py tb_final_modal_adapter --mutation Preset
python verification/scripts/run_final_tests.py tb_final_modal_adapter --mutation Release
python verification/scripts/run_final_tests.py tb_final_wave_envelope --mutation Wave
python verification/scripts/run_music_tests.py --bin C:/Library/modelsim/win64
python model/check_music_pipe.py build/regression/music/tb_music_pipe.csv
./verification/scripts/run_hdmi_reset_tests.ps1
./verification/scripts/run_hdmi_reset_tests.ps1 -NegativeControl
./projects/piano/build.ps1 -EvidenceDirectory build/final-noscreen
./projects/hdmi/build.ps1
python verification/scripts/check_j13_wiring.py --report projects/piano/impl/pnr/piano_performance.rpt.txt --report projects/hdmi/impl/pnr/piano_hdmi.rpt.txt --negative-control --output build/integration/20261016/pins_final.json
./.venv-studio/Scripts/python.exe -m unittest discover -s host -p 'test_*.py'
./.venv-studio/Scripts/python.exe verification/test_dual_host.py -v
python verification/scripts/audit_final.py
```

Python使用本机已配置环境或`C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`；GUI测试使用已有.venv-studio。ModelSim在沙箱内无法加载系统DLL时，应在正常PowerShell环境运行。首次打开HDMI GUI前执行`./projects/hdmi/build.ps1 -PrepareOnly`。

审计保护清单固定在`verification/data/protected_inputs.json`与`upstream_imports.json`，不再依赖未提交的临时基线。摘要额外保存当前源码/测试/约束的合并SHA256清单；原始日志和生成数据仍在build。布局结果属于本次构建观测，未进行多种子统计。

## 外部时序：继续列为未闭合

34个引脚有位置约束、17条命令生效、五类内部余量为正，不能证明全部外部端点及接收边沿已覆盖。以下缺口保留，未通过新增宽泛例外、降频或猜测器件参数隐藏。

| 接口／事项 | 当前模型与待补证据 |
|---|---|
| V22系统时钟／PR1014 | V22为EMCCLK，报告为PRIMARY但仍有通用接入告警；需定位接入段与厂商合法路由。不能据告警断言所有时钟都走普通线，也不据正余量自动豁免 |
| DAC BCK/WS/DIN | 保留本地0～20ns路径限制，尚缺接收器setup/hold、板线偏斜、边沿／负载预算；到引脚延迟不是DAC接收余量 |
| SDA三态输出 | 数据为0，真正切换的是IOBUF.OEN；需要独立核对OE／IO端点覆盖。SCL命中不能代替SDA使能已分析 |
| I2C电气 | 当前SCL推挽、SDA开漏；347.22kHz下数字低／高最短1.44µs，上拉、电容、实际阈值边沿和ACK仍须实测 |
| HDMI板外 | 49MHz转发时钟、245MHz双沿串行／490Mbit/s；当前未证明线缆／通道偏斜、眼图和接收板容限，内部OSER与复位通过不等于电气认证 |
| 异步输入／复位／UART | 按键／UART首级同步及协议有效，但物理抖动、噪声、亚稳态可靠性、两端频差和实际复位脉宽仍待核对 |
| 功放／模拟通路 | 数字尾音和三帧排空已验证，NS4263启停、稳定时间、爆音和实际模拟响应须实测 |
| 约束覆盖／不确定度 | 原例外理由保持；仍需独立未约束端点、例外命中集合、晶振／PLL抖动预算，不能只看命令数量 |

PT8211-S使用16位补码、MSB先发的右对齐LSBJ。发送器名为i2s_tx，不能据名字称为标准Philips的一位延迟I2S；赛题接口口径继续核实。[PT8211官方手册](https://www.princeton.com.tw/Portals/0/activeforums_Attach/PT8211%20V1.7_E.pdf?ver=I8v0SNPIQri_LxlOI2sp7w%3D%3D)给出BCK上限和高电平时间，但未单列DIN／WS相对BCK的tSU/tHOLD；高电平时间tH不能填成数据保持时间，也不能擅自填0。

现有BCK半周期16／17个50MHz系统拍，即320／340ns；48kHz帧为1041／1042拍。外部接收预算应覆盖两个方向及WS边界：

```text
建立余量 = Hmin + dB(min) − dD(max) − tSU(DAC) − Usetup
保持余量 = Hmin + dD(min) − dB(max) − tHOLD(DAC) − Uhold
```

dD/dB须包含各自板线延迟。只由0～20ns本地窗口推算的300ns稳定窗口是可行性粗预算，不是外部签核。不能用divide_by32/33冒充平均1.536MHz的分数节拍BCK。补充模型需保持现有时钟使能架构／本地限制并解释覆盖集合。

PR1014后续最小调查是逐段检查V22入口／PRIMARY路由；若评审独立PLLA重出50MHz，须同时验证LOCK、失锁、时基和生成时钟。不能直接将当前1225MHz VCO的整数分频CLKOUT2当作50MHz（需要÷24.5），也不能让HPD／拔屏复位音频域。

[TI ADS1115手册](https://www.ti.com/lit/ds/symlink/ads1115.pdf)的Fast-mode低电平下限1.3µs，当前数字预算仅多140ns，必须考虑实际电气条件。两旋钮数字采样与平滑不替代静置噪声、中心校准和模拟响应测量。

## 实物待验收与目录收尾

本轮不自动操作下载器、串口设备或Flash。新位流仍需按新表逐键验证，特别是K6；先看音名／高亮，再判断按钮、线束和GPIO。已有照片证明旧版屏幕显示，不等于新位流实屏／听感验收。

耳机先低音量，检查钢琴／经典摇滚吉他、切模式旧尾音、旋钮中心／两端、和弦及持续演奏。测模拟总延迟前核对起止点、阈值和安全测点；桥接扬声器端不能任意接示波器地。实体与将来触摸分别验收，≤10ms基础目标／≤5ms争取项不以数字内部延迟代替。

旧sim副本、编辑器simulation日志、根目录work仿真缓存及两份sources.f清单已移到build，可恢复；工程目录未大改，C独立工程保留。README／PLAN／设计／显示／接线说明维护当前状态，旧实现直接查Git，不另造同功能旧工程副本。

USB触摸、混响、32声部本轮未实现；模拟总延迟、外部时序及新实物效果继续列为待验收，不能据当前位流生成勾选整题完成。
