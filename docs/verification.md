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

## 2026-10-17：合并master验收

将已验证整合提交 `69589a2` 与队友master `e18160e` 合并；保留A独立试听工程、其测试及上位机预设／实时控制／自动试听功能。电脑端同时保留正式固件的有界队列、松键快照、状态失效和不重放保护，按握手能力启用功能。新增操作行使停止按钮跌出紧凑窗口首屏的问题由原测试检出，已调整布局并重跑，未修改测试要求。

合并工作树重新执行149文件严格Verilog-2001编译、8项正式联合回归、host全部81项及双音色协议4项，全部通过；源码布局检查66个唯一有效模块及3个GPRJ通过。原队友TB不改，正式RTL／两入口工程／现有约束与 `69589a2` 的Git内容一致。本轮没有重跑综合／布局布线；上节资源、时序和位流哈希仍属于原构建，不将合并测试冒称新实现或实物验收。

可审计摘要见 [master_merge.json](../verification/evidence/final/master_merge.json)，原始日志保存在本地 `build/master-merge/`（合并工作树归档前复制）。电脑端仍用离屏Qt和内存传输替身，未连接真实COM；模拟整机延迟及外部时序缺口保持未闭合。


## 2026-10-17 第三表情维度整合

本次在队友最新master `aef94e5`上接入明亮度，保留31005底板J13接线、模态钢琴／经典摇滚、16复音和HDMI画面。两个正式入口均启用：旋钮0音量、旋钮1弯音、KEY1明亮度；KEY2继续切换乐器。KEY1短按每次调暗16级，到0后再次短按回127；长按约0.5秒恢复127，复位也恢复127。KEY1不再兼作C4，外接13琴键映射不变。两键同时按下仍会触发KEY2切音色，不再作为第三维恢复手势。

明亮度由FPGA混音后定点低通实现，默认127逐样本保持原PCM；三拍音频流水线使正式缓存合同由R924变为R927，原60个半边沿请求提前量保留，尾音归零后再关闭功放。屏幕观察过滤后的音频，显示不反馈控制。明亮度改变谐波比例和部分能量，不能称为真实力度传感或模拟底噪修复。

新验证入口`verification/scripts/run_expression_tests.ps1`；整合结果与新位流身份见`verification/evidence/expression/summary.json`。旧e18160e基线的31004／旧接线试听包不适用于当前J13接线；请从本次整合后的正式工程构建或使用新包。既有PR1014、DAC完整外部时序、模拟总延迟及新增听感仍需实物验收。PPT第12页的≥3维是扩展目标，基础要求仍为≥2维。


### 本次整合实际验证结果

155份Verilog严格编译；4项第三维测试通过，14,992个单元样本、7,606个兼容链路样本和9,717个当前模态链路样本与独立整数模型完全一致。当前模态三维测试解码19,434个实际DAC字，验证KEY1、KEY2、混合预设、16复音、R927、尾音与静音；默认明亮度与原PCM相同。队友模态适配器和正式HDMI音频隔离测试通过。旧正式I2C测试保留原文，通过显式ENABLE_BRIGHTNESS=0包装验证原R924／KEY1别名合同，不冒充新KEY1操作证据。

两入口Gowin1.9.12.03构建及当前约束检查通过，J13实际布局报告和负向检查通过。无屏Logic16645、寄存器7228、BSRAM80、DSP15.5，setup/hold/recovery/removal/pulse-width最差余量为+1.649/+0.247/+12.855/+1.143/+6.809ns。HDMI Logic20134、寄存器7834、BSRAM94、DSP16，对应余量+0.379/+0.247/+0.834/+0.143/+5.803ns；34端口、17条SDC及12个复位布局落点检查通过。Gowin版本与队友旧报告不同，差异不能全归因于功能改动。

无屏位流SHA256：`e84fa2abe3bbf90f8e8385b924cc34feb47b468be1f8c968ae1b23ae6a7eb872`；HDMI位流SHA256：`7dacdc2c72152199413080f44cacc9774e0bdd3ab19f9f949e844a771530d709`。本机新包为`build/audition/expression3_j13_20261017/`。源代码包含两入口构建和仿真依据，位流／缓存不纳入Git。完整哈希见`verification/evidence/expression/summary.json`；既有队友TB、upstream、引脚和process配置没有修改。新增功能未下载或实物验收；上述报告不闭合PR1014、DAC完整外部时序及整机延迟。

复现新增回归：`./verification/scripts/run_expression_tests.ps1 -ModelSimBin D:/modelsim1/win64 -Python <已安装NumPy的Python路径>`。当前正式测试用`run_final_tests.py tb_final_modal_adapter tb_final_hdmi_isolation --bin D:/modelsim1/win64 --gowin-simlib <Gowin安装目录>/IDE/simlib/gw5a/prim_sim.v`；旧正式合同单独执行`run_final_tests.py tb_final_performance --legacy --bin D:/modelsim1/win64`。

## 2026-10-17 当前：KEY1三音区（取代正式版明亮度操作）

用户确认此前音色异常来自音响。本轮按要求让钢琴/经典摇滚共用三音区：KEY0复位钢琴/中音区，KEY1中→高→低→中，KEY2只切乐器并保留音区。每档13音：低MIDI48～60、中60～72、高72～84；按住旧音换区不移调，松键按原音符/来源释放。PC绝对MIDI独立。HDMI同步音区、琴键名及当前窗口高亮，高音吉他显示12～24品。明亮度暂不启用，正式音频合同为R923有效/R924缓存、提前60个半位边沿。

实际执行结果：

- 严格Verilog-2001编译158文件，0错误；当前工程引用/模块唯一性检查通过。
- 新 `tb_performance_octaves`：两乐器×三音区×13键共78音；消抖/长按只跳一次/环回/复位、同拍换区起音、旧音释放、PC同音与PANIC来源隔离、13实体+3PC满16及排空通过；实际I2C模型，R924和21190个真实串行DAC字逐字对照通过。消抖及UART加速，其余保持50MHz/48kHz。
- 新 `tb_hdmi_octaves`：使用正式2ms消抖和厂商HDMI模型，1ms脉冲被忽略、三档状态进入真实帧，两音色持有音与显示一致；带屏/无屏音频引脚逐拍一致，3307样本，明亮度参数冲突时音区优先。此项ADC值注入，不当作ADC电气验证。
- 新 `tb_panel_octaves`：三档琴键音名、3042个吉他指位像素、每个音可见和高音12/24品标签通过；覆盖UI=1及兼容UI=0。
- 原 `tb_final_display_ui`：两乐器完整实际RTL帧、1841400次像素对照通过，已渲染中档图检查。原 `tb_final_hdmi_isolation`：16声部、HPD/PLL/像素时钟停止/复位的音频隔离通过。
- 原 `tb_final_performance` 通过显式 `ENABLE_BRIGHTNESS=0, ENABLE_OCTAVE_KEY=0` 包装验证其旧KEY1别名合同：真实I2C静音/弯音/故障恢复、20642个DAC字通过。它不替代新三音区测试，原TB未修改。
- 两入口重新综合、布局布线、位流生成，当前约束五类时序、process一致性和两份实际J13引脚报告通过；原HDMI复位落点检查通过。145份受保护清单文件、34份导入清单文件相对本轮Git基线内容不变；A核心/ROM、C输入算法、原TB、约束及process未改。历史清单含不同检出的LF/CRLF哈希，本轮保护检查按Git基线内容，当前仿真/构建依赖均按实际字节SHA256校验。

| 入口 | Logic / FF / BSRAM / DSP | Setup / Hold / Recovery / Removal / 脉宽最小余量(ns) |
|---|---|---|
| HDMI | 20467 / 7969 / 94 / 13.5 | +0.370 / +0.193 / +0.834 / +0.143 / +5.803 |
| 无屏 | 16382 / 7358 / 80 / 13 | +2.470 / +0.053 / +16.249 / +0.627 / +6.809 |

HDMI资源检查34端口/17约束；无屏25端口/10约束。上述为当前约束范围内报告，不是宽裕时序或整机签核；既有PR1014、完整DAC板外时序和输入至模拟输出总延迟仍待实测。本轮未重跑无变更的完整A/PC测试，也未操作下载器。音区切换不计为第三表情维度。

本机下载包 `build/audition/octave3_j13_20261017/`：

- HDMI：`hdmi_octave3_j13.fs`，SHA256 `f813f2d0187c9599d0640683c6eaaef2deff1531918429894581dfd46df5ad5d`。
- 无屏：`piano_octave3_j13.fs`，SHA256 `4ccb941929d959f77738d0e97798cc505d3499dd6a04b962be905083fa0f03c9`。
- 同目录 `试听说明.txt` 是上板逐项验收步骤，`manifest.json` 记录位流/源码身份。新位流实物试听尚未验收。

完整摘要及原始日志：[三音区证据](../verification/evidence/octaves/summary.json)。本轮工具为Gowin V1.9.12.03、ModelSim SE-64 10.6e。重现时以实际工具路径覆盖脚本默认值：

```powershell
./verification/scripts/check_verilog.ps1 -ModelSimBin D:/modelsim1/win64
python verification/scripts/run_final_tests.py tb_panel_octaves tb_performance_octaves tb_hdmi_octaves tb_final_display_ui tb_final_hdmi_isolation --bin D:/modelsim1/win64 --gowin-simlib C:/Gowin/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v
python verification/scripts/run_final_tests.py tb_final_performance --legacy --bin D:/modelsim1/win64
./projects/hdmi/build.ps1 -Gowin C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe -Python <实际Python路径>
./projects/piano/build.ps1 -Gowin C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe -Python <实际Python路径> -EvidenceDirectory build/octaves-noscreen
python verification/scripts/check_j13_wiring.py --report projects/piano/impl/pnr/piano_performance.rpt.txt --report projects/hdmi/impl/pnr/piano_hdmi.rpt.txt --output build/octaves-noscreen/j13-check.json
python verification/scripts/summarize_octaves.py
```

## 2026-10-17 本机同步expression后的复测与界面定稿

本地master由`aef94e5`快进到远端`c1da9a3`，再合入`cleanup/expression-brightness`的`a0684e4`，合并提交`0cca748`。合并树SHA为`a5f6939bc377bc5eba3f7a49745c30bae528a565`，与expression最新分支完全一致；无冲突、无人工RTL修补。本轮仅本地操作，未推送、未烧录。

本机ModelSim SE-64 10.6e、Python3.12.14实际重跑结果：

| 检查 | 实际结果 |
| --- | --- |
| 严格语言编译 | 158文件，`-vlog01compat -pedanticerrors`，无SystemVerilog模式 |
| `tb_panel_octaves` | 三音区、琴键字形、3042个指板像素检查通过 |
| `tb_performance_octaves` | 两乐器78音、换区/旧音释放/PC隔离、满16声部、真实ADC、R924及21190个DAC字通过 |
| `tb_hdmi_octaves` | 实际2ms消抖、三音区帧状态、两音色、持键所有权、3307个音频样本一致 |
| `tb_final_display_ui` | 两模式真实模态帧，1841400个像素精确匹配；测试的是现有深色UI，不是新概念图 |
| `tb_final_hdmi_isolation` | 满16声部、HPD/PLL/像素停钟/复位，369个音频样本一致 |
| `tb_final_performance --legacy` | 显式关闭新音区/明亮度操作的旧合同兼容，20642个DAC字通过；不当作新KEY1证据 |

初次在沙箱内启动ModelSim报DLL重定位/进程重定向错误，尚未开始RTL编译；相同工具在获准的非沙箱进程中正常启动并完成全部检查。未更改系统DLL、许可、脚本或测试来绕过错误。

保护检查：同步前保存的99份既有TB/上游TB及用户未提交文件SHA256全部不变；保留`.vscode/config.json`的用户修改和未跟踪的`verification/evidence/hdmi/`。原有引脚、SDC、物理布局约束没有本轮额外修改。

队友证据独立核对：266份输入中160份字节一致、106份仅LF/CRLF行尾差异（分别重算两种行尾哈希确认），没有其他内容差异；全部报告文件哈希一致。两个`octave3_j13_20261017`位流与上节公布的SHA256完全一致。不得把换行归一化比较说成266份原始字节完全一致。新本机测试自己的输入清单保存在`build/regression/final/*_inputs.json`，同步核对摘要为`build/expression-sync/sync_audit.json`。

实际复现命令（本机路径）：

```powershell
./verification/scripts/check_verilog.ps1 -ModelSimBin C:/Library/modelsim/win64
& 'C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' verification/scripts/run_final_tests.py tb_panel_octaves tb_performance_octaves tb_hdmi_octaves tb_final_display_ui tb_final_hdmi_isolation
& 'C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' verification/scripts/run_final_tests.py tb_final_performance --legacy
```

本机HDMI仿真使用默认Gowin V1.9.12.04的`gw5a/prim_sim.v`；未重跑Gowin综合/布局布线，原三音区包的实现仍属于队友V1.9.12.03构建。A/PC完整套件未重跑，不声称全面回归、时序签核或实物验收。

另保存用户选定的`display-touch-concept.png`及[简洁界面与触摸设计](display-rgb.md)，只改文档/概念资产；新界面和FPGA USB主机尚未实施。触摸描述符、速率、报告、31005电气连接和真实延迟是独立待验证项。

## 2026-10-17 简洁界面实现与独立触点处理

用户要求“完成计划”后实施。正式HDMI继续使用唯一`instrument_panel_ui`，改为暖白/浅灰、淡黄高亮，钢琴琴键与吉他六弦/13半音垫同步切换。新增`instrument_ui_map`供绘制与触点共同命中，`display_feedback`在帧提交更新7帧残影、局部拨弦和峰值保持/回落。输出仍是原3级像素流水及真实PCM波形，不改变音频R923/R924。README和显示说明的两图来自`tb_simple_display_frames`实际RGB输出，概念图单独保留。

`touch_contact_tracker`目前只接受已解码的5点完整快照。按触点ID稳定匹配内部来源，先松旧音再滑奏，换区保留旧音高，切模式后旧触点等待抬手；控件只在接触开始时发一次。断连/坏报告按来源取消，背压下保持有效事件。模块尚未进入正式顶层；USB主机、HID解码/组包、坐标适配、USB跨域及正式输入/延音控制汇合未完成。用户明确回复新线尚未接电脑；本轮只读PnP枚举未发现可确认的触摸屏。

本机ModelSim10.6e/Gowin1.9.12.04/Python3.12.14实际验证：

- **166文件严格Verilog-2001通过**，未使用SV模式。
- 5项新常规测试：`tb_simple_ui_map`覆盖两模式1228800像素及控件边界；`tb_simple_ui_states`覆盖三音区/3042独立指位检查；`tb_display_feedback`检查帧沿更新、淡出/峰值/复位；`tb_simple_display_frames`检查两种真实模态音频的完整帧、1841400像素的流水匹配和新配色/模式状态；`tb_touch_contact_tracker`核对28条精确事件、五指、来源重排/同音、滑奏/换区/模式、满16席真实分配器、断连/重复ID、背压和待接受事务复位。
- 5项既有功能回归通过：`tb_performance_octaves`、`tb_hdmi_octaves`、`tb_final_wave_envelope`、`tb_final_hdmi_isolation`、`tb_final_performance --legacy`。旧performance仍是显式兼容操作配置；当前三音区/R924由前两项证明。新增`--mutation TouchRelease`故意丢松键，检查器以`FAIL missing touch event`拒绝，故障仅生成到build。
- 既有队友TB和上游TB保持原文。原`tb_final_display_ui`/`tb_panel_octaves`的固定深色/旧坐标断言不作为新视觉验收；它们未改写成新期望，新像素/音区检查由上述独立测试覆盖。A/PC完整套件及17次串行恢复未在本轮重跑。
- 工程布局检查71个唯一有效模块及3个既有GPRJ通过；HDMI工程由真实Gowin构建另核对新增模块。当前实际J13报告检查通过。

最终HDMI完整综合/布局布线，GW5AT-LV60PG484AC1/I0，50/49/245MHz：Logic **20704/59904**、寄存器 **8059/60780**、BSRAM **94/118**、DSP **13.5/118**、PLLA1。相对三音区包Logic+237、寄存器+90，BSRAM/DSP不变。最差setup/hold/recovery/removal/pulse-width为 **+1.303/+0.124/+0.834/+0.143/+5.803ns**；34实际端口、17条SDC和12个复位FF/LUT落点检查通过。两次构建中第二次修正吉他文字重叠，最终报告与该源码匹配。所有既有引脚、SDC/例外、process及音频核心保持不变；本轮未重建未改变的无屏工程。

独立触点模块仅综合：**930Logic、309寄存器、0锁存器、0BSRAM、0DSP**。第一次发现两个常数乘7槽地址被推成DSP，改为移位减法后重跑综合和正/负向测试，网表无乘法DSP。该综合未设板级引脚/外部时序，不生成下载文件，不能加到正式HDMI报告后声称USB整机已实现。

本轮带屏位流：[piano_hdmi.fs](../projects/hdmi/impl/pnr/piano_hdmi.fs)，SHA256 `23b8d73c5ae0049b9f55db50dc75144a82c7b2fab65e02652ae2a5fe537063f8`。PR1014、DAC完整外部时序、HDMI眼图/接收器兼容和整机模拟延迟仍未闭合。保持/移除余量较薄，不称全面签核。未烧录、未实屏验收、未推送。

可审计摘要及本轮日志：[ui_touch/summary.json](../verification/evidence/ui_touch/summary.json)。原有用户修改和未跟踪HDMI证据保留；源/约束身份、检查器/输入清单、主报告和日志均与本轮结果关联。复现：

```powershell
./verification/scripts/check_verilog.ps1
python verification/scripts/run_final_tests.py tb_simple_ui_map tb_simple_ui_states tb_display_feedback tb_simple_display_frames tb_touch_contact_tracker
python verification/scripts/run_final_tests.py tb_touch_contact_tracker --mutation TouchRelease
python verification/scripts/run_final_tests.py tb_performance_octaves tb_hdmi_octaves tb_final_wave_envelope tb_final_hdmi_isolation
python verification/scripts/run_final_tests.py tb_final_performance --legacy
./projects/hdmi/build.ps1
```

独立触点综合可在build中创建只含`touch_contact_tracker.v`/`instrument_ui_map.v`的相同器件工程，以tracker为顶层执行`run syn`；本机本轮临时工程为`build/expression-sync/touch-synthesis/`。USB下一步须先获得实际设备描述符/报告，再实施主机/HID与正式汇合，顺序已落到PLAN第7.1节。
