# 当前验证与验收边界

## 2026-10-25 明亮度合并与完整实现复核

本次 master 提交合入队友 `1bc0203` 的双级对数明亮度，并保留帧弯音预计算、触点共用译码和 USB 修复。127档逐样本保留原音；R958（19.16µs）/976拍准备窗余18拍，32声部、48kHz、钢琴/吉他、三效果和接线保持。

正式完整重建通过原39引脚/28条约束检查，采用P2/R2/C0；Setup/Hold/Recovery/Removal/Pulse为 **1.076/0.128/0.642/0.143/5.799ns**。Logic44614/59904、FF20486/60780、BSRAM93/118、DSP37/118。与合并前R955优化版相比，新增功能有资源代价，不能称所有资源或时序都改善。

245份严格Verilog-2001、16项功能/差分/DAC检查及滤波、DAC和引脚故障控制通过；长音频回归使用独立核验等价的仿真ROM，综合仍使用厂商原语。252份旧保护文件未变，process仅Place由3改2，CST/SDC及全部既有TB保持。自动系数ROM原方案119条未布线；局部逻辑映射P3仍2条未布线，均未晋升。

当前fs SHA256 `604f12e3299b479ddbf6a9805ad73670186e884b6ed58a69ddf176035ac37295`；只由 `projects/hdmi/piano_hdmi.gprj` 构建生成，本次不上传fs或打下载包，不烧录。证据集中在 `verification/evidence/brightness_response/summary.json` 及同目录 `merged_details.zip`；临时备份与候选完整工程已删除。

实物USB触摸/两条整机延迟、蓝牙首音、PR1014及完整DAC板外时序仍待验收；屏幕延音/模式/音区控件与远程APPLY仍未接通。固定ADSR预设D/S与PT8211右对齐的赛题口径未关闭。旧坐标TB在基线与新版均失败，未修改或计为通过。下方R955位流、旧资源及“未推送”均为形成时的历史快照，不能替代本节的整合结果。

系数表按高云SUG550-2.4E第5.17节的局部 `syn_romstyle="logic"` 实现；没有放宽时序例外。依据：[官方综合手册](https://cdn.gowinsemi.com.cn/SUG550E.pdf)。

| 对照 | Setup/ns | Hold/ns | Recovery/ns | Removal/ns | Pulse/ns | 说明 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 合并前R955优化版 | 1.111 | 0.162 | 0.545 | 0.210 | 5.799 | 历史对照 |
| 冻结网表p2_r2_c0 | 1.153 | 0.128 | 0.642 | 0.143 | 5.799 | 独立候选 |
| 冻结网表p4_r2_c0 | -0.297 | 0.048 | 0.561 | 0.143 | 6.067 | 未通过，不采用 |
| 正式完整重建 | 1.076 | 0.128 | 0.642 | 0.143 | 5.799 | 当前正式结果 |

候选与正式重建余量一致：`false`；资源一致：`true`。源代码构建检查点为 `284e7ba2558b34ebf1592a30bbe6c97687b0331e`，候选使用冻结网表，正式重新综合；Setup候选1.153ns、正式1.076ns，采用正式值，不混用候选数字。最终发布只追加证据与文档，不将构建时快照改写为上板验收。

完整复现顺序见 [明亮度验证命令](brightness-response.md#验证与复跑)，当前汇总脚本的基线为 `284e7ba2558b34ebf1592a30bbe6c97687b0331e`。

## 2026-10-25 多方案时序与资源对照

本轮用户授权修改并要求临时备份最终删除；目标是保持原功能，比较整体时序/资源，而非只改最短的一段。正式只修改三个既有RTL：`instrument_panel_ui.v`、`instrument_display.v`、`touch_contact_tracker.v`，没有增加生产模块。音色A核心/ROM、所有既有TB、CST/SDC/process、接线和音频R955保持。

| 方案 | Logic | Setup/ns | Hold/ns | Recovery/ns | Removal/ns | Pulse/ns | 结果 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 基线 | 44000 | 0.300 | 0.191 | 0.642 | 0.143 | 5.799 | 对照 |
| A：帧弯音预计算 | 44205 | 0.001 | 0.196 | 0.642 | 0.143 | 5.799 | 未采用 |
| B：触点独热读 | 43945 | 0.776 | 0.060 | 0.642 | 0.143 | 5.799 | Hold过薄，未采用 |
| C：并行命中 | 44186 | -1.515 | 0.083 | 0.669 | 0.143 | 5.799 | 时序失败，未采用 |
| A+B，P3/R2/C0 | 44120 | 1.111 | 0.162 | 0.545 | 0.210 | 5.799 | 空间换时序，采用 |
| B，时钟布线顺序1 | 43945 | 0.776 | 0.060 | 0.642 | 0.143 | 5.799 | 无收益，未采用 |
| 同步BCD ROM+B，P3/R2/C0 | — | — | — | — | — | — | 54条未布线 |
| 同一ROM网表，P3/R2/C1 | — | — | — | — | — | — | 54条未布线 |
| 同一ROM网表，P4/R2/C0 | — | — | — | — | — | — | 62条未布线 |

八种方案/配置中，A+B最初没有满足Logic≤44000的严格面积门槛。本轮按用户此前“资源换时间”的方向明确保留小幅面积取舍，再单独声明确认门槛（Setup≥1.0ns、最薄≥0.150ns、Logic≤44200、BSRAM93/DSP35.5及延迟不变）并独立全量重建。候选、独立确认、正式重建三次资源和五类余量完全一致；位流原字节因构建身份不同不宣称相同。新正式资源Logic44120/59904、FF20376/60780、BSRAM93/118、DSP35.5/118；相比基线Logic+120、FF−6、RAM/DSP不变。Hold和Recovery有所下降，最薄由143提高到162ps，仍偏紧。

同步ROM试验的综合LUT35303→34572、BSRAM增加1；实际综合网表pROM的256个INIT表项、256次厂商原语读取及512次CE保持均核验，损坏第200项被拒。尽管功能等价，三组实现仍布线失败，未把它晋升为正式代码。不得把其综合节省或失败位流与正式版本混称。

### 本轮实际验证

- 正式242份Verilog-2001（`-vlog01compat -pedanticerrors`），编译0错误/0警告；既有TB原字节保持。
- 全65536个弯音码，与固定Git原版及独立整数模型一致；196608次保持检查，覆盖负极值/舍入/默认组合兼容/停钟复位。
- 2456173拍实际新旧RGB/DE/HS/VS/CDC/帧快照差分，覆盖钢琴及吉他全帧、异步时钟、参数换帧和停钟复位；像素流水线没有加拍。
- 触点N=1/5/6/15共240000周期逐拍对照；正式旧触点+真实分配器、USB线级枚举/CRC/NAK/六触点以及4轮断连/PLL恢复均通过。
- 正式三音区/两乐器3042组独立指位检查、32769档电平显示和17轮HDMI恢复通过。
- A+B完整正式32声部/三效果回归通过，使用单独证明等价的仿真ROM，实际综合仍用厂商原语。full32=13417、串行字27274、仅湿声尾音8904；六触点+13实体+13PC满32、BLE第33音抢占及来源隔离通过。所有非生成输入与正式源码逐项哈希映射一致，不是假称所有长仿真都用厂商ROM。
- 数字帧内更新、数字晚帧和触点槽位丢失三种正式故障均被对应检查拒绝；未采用的命中边界、ROM错误表项/复位屏蔽及综合网表INIT错误也被拒。
- 原39个引脚、28条约束、12个HDMI局部复位落点检查通过，USB8项及J13负向检查通过。DAC发射正常/错误DIN/错误WS控制通过；完整板外审计仍为`INCOMPLETE_EXTERNAL_EVIDENCE/signoff=false`。

旧 `tb_panel_octaves.v` 检查`x=736,y=100`的旧文字位置及旧配色，在修改前UI和正式新UI均于1ns报`FAIL range label glyph`。当前文字在y=108；此TB未改、未放宽断言，也未算通过。新布局由`tb_simple_ui_states`和独立新旧全帧差分覆盖；不是宣称所有历史TB都适用当前界面。

### 功能接入审查与边界

32声部是两组16并行，三效果串在最终混音后，湿声尾音参与PA保持及帧排空；实体/USB/PC/BLE来源独立取消，三路ADC的音量/连续弯音/明亮度真实进入音频。正式每声部都有`instrument_env`，但钢琴A64/R4096、吉他A16/R2048，均D1/S65536，D段不实际降幅，主要自然衰减来自模态。应确认这种固定预设对ADSR展示的口径，不能说已有可调四阶段参数或延音踏板。

屏幕琴键已进入正式数字链路并通过仿真；屏幕模式/音区/延音控件事件仍未汇入控制仲裁。PC/BLE有HELLO、音符/力度/松键、PANIC和状态查询，不支持远程APPLY配置；第一阶段原约定为电脑演奏和状态，配置仍是固件预设。导奏保持关闭。USB实物六指/滑奏/方向、偶发串键及蓝牙首音仍待实测，不能据数字测试宣称已验收。

音频缓存时刻仍R955（50MHz约19.1µs），976拍准备窗余21拍；新触点路径没有增加握手拍数。没有在这一轮降低音频缓存拍数，也不能据此证明实体/触摸整机≤10ms。实体与触摸需分别测量到模拟输出；PR1014、DAC接收器建立保持、板级偏斜/边沿、PT8211-S右对齐与赛题I2S口径仍未关闭。原生时钟/约束没有通过放宽例外来换通过。

### 当前身份与复现

正式fs SHA256 `edb155011e52df4d7670275ca1e263f0bcf72248f1c0161000c5dc3e874d761c`；唯一工程 `projects/hdmi/piano_hdmi.gprj`。Git基线df0e894加未提交改动，不能只凭HEAD复现。证据集中于`verification/evidence/timing_candidates/summary.json`。未提交/推送、打下载包或烧录，实物尚未验收。本轮临时备份及候选完整工程已删除。

```powershell
$py = 'C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
./verification/scripts/check_verilog.ps1
& $py -B verification/scripts/check_timing_candidates.py tb_frame_bend_equivalence tb_frame_display_equivalence tb_touch_mux_equivalence --out build/regression/timing_candidates
& $py -B verification/scripts/run_final_tests.py tb_dual16_hdmi tb_touch32_audio --functional-rom --out build/regression/timing_audio
./projects/hdmi/build.ps1
& $py -B verification/scripts/check_dac_timing.py --run --allow-incomplete
```


## 2026-10-22 构建清单收拢与局部布局试验

本轮按用户批准的小步方案执行；HTML仅为上一轮评审的对比展示，不是工程依赖。结论收录到本文件，不另增Markdown报告。**正式RTL、全部既有Verilog TB、原CST/SDC/process、接线、音色和R923/R953合同均未修改，也未推送或烧录。**

### 正式保留的改动

- `build_inputs.py`统一正式构建、源码快照和PNR试验的输入枚举，补齐时序解析器等依赖；ROM、原/生成约束、冻结网表和文件变更均有哈希检查。
- 修复批跑流程：Gowin的`run pnr`在原RTL工程中可能隐式重新综合；`set_file_enable/add_file`又会自动保存工程。现在先在**隔离副本**中准备仅网表启用的GPRJ，再冻结清单，执行阶段不改GPRJ；日志必须明确跳过综合，网表哈希必须不变。没有放宽原检查来接纳失败批次。
- HDMI工程只移除5个不参与正式入口的引用：`instrument_uart_piano_top.v`、`piano_13key_top.v`、`piano_performance_top.v`、`voice_dds.v`、`voice_adsr.v`。工程RTL引用64→59；源码仍供旧测试/独立入口使用，未删除。没有通过合并文件或删除测试掩盖复杂度，也不把引用减少说成节省硬件。

### 同网表、同process的局部试验

| 试验 | Setup/ns | Hold/ns | Recovery / Removal / Pulse/ns | 结论 |
| --- | ---: | ---: | --- | --- |
| 冻结网表基线 | 0.121 | 0.070 | 0.834 / 0.143 / 5.803 | 对照 |
| 波形地址寄存器移到R44C36 | 0.669 | 0.047 | 同基线 | Hold变差，不采用 |
| 声部8包络的两个LUT限制到R22C127 | 0.374 | 0.070 | 同基线 | Setup改善，候选保留但不进入正式工程 |
| 包络方案独立复跑 | 0.374 | 0.070 | 同基线 | 与候选结果一致 |

候选只在合成后限制`g_env[8].u_env/n860_s3`和`next_error_5_s1`，不改逻辑表达式或流水线。包络候选Logic23320，其他资源与基线一致；这不是预先约定的严格资源计数相同条件。加上最薄Hold仍只有70ps、目标单元已不在打印的前N条关键路径中而缺少逐落点独立核对，**本轮不晋升候选、不修改正式物理约束**。不能用候选Setup描述当前正式位流。

第一次复制网表仍触发综合、第二次Tcl修改试验GPRJ的批次都被身份检查拒绝，失败记录保留在`build/timing_local_20261022/`，不作为通过证据或下载入口。最终有效试验为`frozen2_*`，每次均核对网表原字节、全部输入哈希、34端口/17项约束/12个既有复位落点；实验和正式工程的原约束未放宽。最薄Hold的寄存器→波形RAM路径、包络高扇出长布线以及PR1014仍需后续处理，DAC外部时序等既有缺口未消失。

### 实际验证与当前正式位流

187文件严格Verilog-2001编译、13项Python/Tcl流程测试、76个有效模块/4个GPRJ检查通过。重新执行三效果HDMI集成（满16声部、27180个DAC字、R953/音区/旋钮/视频隔离）和波形包络回归，以及17次HDMI复位恢复和坏通道负向检查。其余上轮功能测试仅核对依赖哈希，未冒称本轮全部重跑；684份本轮起点已有文件保持逐字节一致。

按原约束/process完整重建正式工程后，资源仍为Logic23321、寄存器9250、BSRAM92、DSP24.5；五类最差余量仍为 **0.121 / 0.070 / 0.834 / 0.143 / 5.803ns**。未实例化源文件移除后，综合器对部分`bend_ratio`网络重命名，综合网表不逐字节相同；本轮依据未改RTL、回归及实现检查，不宣称已做形式等价证明。

当前正式位流仍是`projects/hdmi/impl/pnr/piano_hdmi.fs`，本轮重建SHA256 **`50022382ce0d5f53a4f4e7a03829e760428b68ffa27c8f4f6d7640774ea46ce1`**。改动前位流及报告保存在`build/timing_local_20261022/formal_before/`。机器摘要见[局部试验与保护清单](../verification/evidence/timing_local/summary.json)。仅通过现有数字约束，不代表外部接口、触摸、听感或整机延迟实物验收。

复验入口：`python verification/scripts/test_pnr_sweep.py`、`python verification/scripts/check_source_layout.py`、`./verification/scripts/check_verilog.ps1`、`python verification/scripts/run_final_tests.py tb_effects_hdmi tb_final_wave_envelope`、`./projects/hdmi/build.ps1`。隔离批跑仍用`projects/hdmi/sweep_pnr.ps1`；不可把生成的试验GPRJ复制回正式工程。

## 2026-10-22 队友master与三效果合并

用户确认本地合入master `e06e344`和效果器分支`f314bc0`，默认开启轻效果，不推送、不烧录。实际合并提交为`a36a780`、`301da9d`，作者沿用仓库历史身份1HFGL；未设置全局Git身份。原有未提交优化、新接线和用户配置已恢复，仍保留在工作区，**当前受测内容不能仅用这两个合并提交表示**，以[本轮源码／证据清单](../verification/evidence/merge_effects/summary.json)为准。恢复用stash `f49f1206adf7df1f2f155a1eb508ec89a0dc36c1`仍保留。

### 实际整合及边界

- 正式入口只有`projects/hdmi/piano_hdmi.gprj`／`piano_hdmi_top`；无屏顶层只作既有仿真对照，不重新发布无屏产品。
- 保留本地浅色钢琴／吉他双画面、动效、ROM重排、节拍／串行／事件优化。五黑键仍为C18/E19/D20/F15/F16，八白键和ADC不动；原SDC、复位布局和process不变。
- 队友三效果RTL原文接入：明亮度准备→Chorus→Delay→Room→缓存。混响／延迟／合唱不是新增声部。默认明亮度127，轻效果比纯干声低一些；调小旋钮不会立即消除之前存入的回声。
- 保留触摸明亮度准备接口、扩展74位帧状态，不叠加队友旧深色顶部滑条。正式USB输入仍断开；旧深色视觉TB原文保留，但不作为新简洁布局的验收测试。真实触摸仍未接通。
- 队友历史提交携带的`build/audition/*20261017/`、两入口资源与证据仅作历史，**不可拿旧接线位流配当前线束下载**。

### 本轮重新执行的检查

- 187份源码／测试严格Verilog-2001编译，无SystemVerilog模式；16项功能测试通过，其中3项明确使用`--dry`的旧合同，不冒充三效果合同。
- Chorus／Delay独立整数参考851000组×6配置；Room 505192组×3比例，包含正负满幅、随机、插值／LFO转折回绕、忙拒绝、脏RAM和逐流水阶段复位。
- 正式48kHz三效果链13571个样本逐级对照参考；满16声部、两音色、音区、旋钮、27180个DAC串行字、HPD／PLL失锁／像素停钟、脏状态复位检查通过。测试旋钮值注入归一化边界，不能当作本次真实ADC实测。
- R923原始样本有效，R953缓存；最小976拍准备窗余23拍（0.46µs），未见欠载／效果器overrun。直达音未等待160ms回声周期；19.06µs内部计算时间不是整机模拟延迟。
- PA加速130000样本测试：92160样本有尾声状态、83620个零输出间隙没有错误静音，最终按真实DAC帧排空。故意删除效果器尾音保持，原样TB正确报错；该加速测试不测整机延迟。
- 简洁UI完整帧1841400像素比对、双模式三音区、3042处指板检查、帧域动效／电平及波形倍率通过。独立触点测试通过，不表示USB触摸接入。
- HDMI 17次启动／恢复及恢复后坏通道负向检查通过；15路外设引脚／34个正式端口核对、4项引脚故障注入通过。
- 226份合并前受保护文件逐字节不变，包括队友TB、C独立工程、合成／ROM／输出优化、约束和用户配置。另核对116份队友新增／既有测试及效果器原文，仅按Git平台换行归一比较，未改其测试断言。

### 最终正式构建

Gowin1.9.12.04，GW5AT-LV60PG484AC1/I0 Version B，50MHz系统／49MHz像素／245MHz串行；ModelSim10.6e。完整构建两次，资源与五类最差余量一致；第一次之后仅恢复Git暂存造成的LF/CRLF变化，最终以第二次源文件哈希和位流为准。

| 指标 | 合并前干声基线 | 当前三效果 |
| --- | ---: | ---: |
| Logic / Register | 20513 / 8030 | 23321 / 9250 |
| BSRAM / DSP | 72 / 13 | 92 / 24.5 |
| Setup / Hold (ns) | 0.063 / 0.179 | 0.121 / 0.070 |
| Recovery / Removal / 脉宽 (ns) | 0.832 / 0.143 / 5.803 | 0.834 / 0.143 / 5.803 |

新功能净增加20块BSRAM，还余26/118块；与队友未采用本地ROM重排的114块结果不是同输入优化实验。保持余量降低，不称“时序全面改善”。当前位流`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 **`a27aa8b48599f62dd1001825f52afd0b80de3130c5871b583ffd9489d4e9fc0b`**。合并前位流及报告保存在`build/merge_effects_20261022/baseline/`，仅供回退。

### 审查结论及未闭合项

本轮合并质量评分8/10（仅针对这次集成，不是产品验收）：未发现需要改动队友效果器公式的新功能缺陷。中等风险为波形RAM地址的0.070ns保持余量，以及原PR1014／DAC外部时序覆盖缺口；不改约束掩盖它们，后续需针对实际路径和板外接口继续验证。UI旧控件与当前坐标的整合明确留到USB阶段，不把缺失入口包装成可用功能。实物听感、接线连续性、显示兼容性和整机≤10ms仍未验收，未推送、未下载。

汇总复验：`python verification/scripts/check_effects_merge.py`（核对已生成测试、PNR、引脚及保护清单，不替代运行这些测试）。功能命令见README，所有输出在`build/regression/`和`build/hdmi/`，汇总在`verification/evidence/merge_effects/summary.json`。

## 历史：队友三效果验证（2026-10-17，非本机当前构建）

171文件严格Verilog-2001、9项测试、851000输入×6种配置通过；三效果正式链路13571样本逐级匹配独立整数参考，其中5031样本为Chorus输出零但Delay仍有回声。256份已有受保护文件逐字节不变。新单元覆盖多次LFO转折/回绕、插值、正负满幅、脏RAM/流水线复位及拒绝忙时输入。加速130000样本的完整PA测试：92160样本尾声保持、83620个零间隙未截断，最终真DAC帧排空静音；不把加速测试当作整机延迟。原混响兼容5971样本、干声明亮度8893样本参考仍一致。

| 指标 | HDMI | 无屏 |
|---|---:|---:|
| Logic / Register | 23097 / 9210 | 18719 / 8502 |
| BSRAM / DSP | 114 / 25 | 100 / 22 |
| 缓存 / 最小准备窗 | R953 / 976 | R950 / 976 |
| Setup / Hold / Recovery / Removal / 脉宽(ns) | +0.248 / +0.113 / +0.834 / +0.143 / +5.803 | +2.162 / +0.046 / +13.111 / +1.296 / +6.809 |
| 已检查引脚 / 生效约束 | 34 / 17 | 25 / 10 |

正式48kHz集成验证包含16个有声声部、两音色、音区、旋钮、串行DAC精确输出及HDMI拔插/丢锁/停钟隔离。模型注入边界和原测试兼容模式见[三效果说明](delay-chorus.md)。9项测试具体结论、当前输入哈希、文件来源与位流SHA256见[本轮摘要](../verification/evidence/effects/summary.json)。原混响包和证据未改。

带屏BSRAM114/118，只剩4块；数字采样准备余量23拍不等同于完整系统时序裕量。Gowin1.9.12.03两入口通过当前约束检查，仍有PR1014、完整DAC外部时序、电气/模拟延迟及实物听感待核验；未代为下载或推送。不把历史包/兼容配置结果当作新效果的硬件实测。

## 此前：轻混响验证（2026-10-17）

本轮Gowin1.9.12.03，50MHz/48kHz、16声部不变；新增混响默认开启。166文件严格Verilog-2001编译通过；7项测试区分当前湿声、显式干声和历史兼容；505192组输入同时核对3种比例；正式链路5971样本与整数参考一致，其中2956个样本为源输入零时的湿声。250份受保护既有文件未改。原触摸测试在显式干声模式下通过8893样本独立参考。

| 结果 | HDMI | 无屏 |
|---|---:|---:|
| Logic / Register | 22303 / 8717 | 17933 / 8009 |
| BSRAM / DSP | 104 / 20 | 90 / 17 |
| 缓存拍数 / 最小准备窗 | R936 / 976 | R933 / 976 |
| Setup / Hold最差余量(ns) | +0.534 / +0.183 | +1.021 / +0.049 |
| Recovery / Removal / 脉宽(ns) | +0.834 / +0.143 / +5.803 | +13.927 / +0.719 / +6.809 |
| 已检查引脚 / 生效约束 | 34 / 17 | 25 / 10 |

全部结果及固件SHA256见[混响摘要](../verification/evidence/reverb/summary.json)。干声对照复用上轮位流，未冒充本轮重建。完成了仿真、综合、布局布线和当前约束检查，尚未代为下载/试听，仍有PR1014及完整DAC外部时序、电气和整机模拟延迟待核验；无屏Hold余量较小，不称时序宽裕。完整试听和复现命令见[混响说明](reverb.md)。

## 以下为混响接入前的阶段记录

最新2026-10-22接线版结果见本文末节[五黑键引脚迁移与Git只读同步](#2026-10-22-五黑键引脚迁移与git只读同步)。唯一正式入口为HDMI；本轮只迁五黑键引脚，不改音色公式或音频时刻。10月18日优化及早期两入口数据保留其时间范围，不能用旧引脚位流/旧资源冒充最新结果。

**当前结论：仅继续实现HDMI正式工程；资源小幅下降，布局策略之间仍有Setup/Hold取舍，不能称时序全面改善。新位流尚未下载，实物验收和完整外部时序仍未完成。** 工作区存在未提交改动，以最新审计的源码/约束/工具哈希为准，不能只用Git HEAD表示受测内容。

## 早期实现记录（后续更新见文末）

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


## 2026-10-17 触摸明亮度板卡侧准备版

范围：KEY1三音区、KEY2钢琴／经典摇滚保持；HDMI上方加入明亮度滑条／原音按钮、接收规范化主触点的状态机及音频采样域平滑。默认127逐样本保留原音；HDMI R927，无屏R924。屏幕当前没有触摸线，USB主机／枚举／HID／坐标校准尚未实现，顶层输入接断开常量，显示“触摸关”。不能把本节证据当成物理触摸、第三维实物验收或整机延迟结论。

- 严格Verilog-2001：162文件，0编译错误／警告；未修改旧测试。
- 9项仿真：触摸2111份报告及全部1024个横坐标；捕获／滑入不触发／端点／原音／越界／断连／超时／复位；实际HDMI顶层两乐器16声部、双旋钮独立、R927、17804个串行DAC字、视频失锁／断开／停钟、有限尾音；三张真实RGB帧含3072个滑条所在行像素检查和帧原子更新。原音区、原UI、原按键明亮度及原音视频隔离回归通过。HDMI动态测试使用规范化报告仿真注入，未执行USB通信；ADC参数注入未宣称重跑真实I2C。
- 独立Python整数参考：14992个滤波单元样本＋8893个本轮整合样本逐点一致，含538个精确旁路样本、5319个实际改变样本和2937个满16声部样本。全暗释放后状态精确归零。触摸改变谐波／能量但不写音量增益或弯音比。
- 相对已发布a0684e4：192份受保护文件（模型／ROM／音频滤波／原约束／上游／既有TB等）无内容变化；原UI的57字及标题点阵逐行一致，仅填6个空槽。源码／日志输入身份随证据保存。
- Gowin1.9.12.03已完成HDMI断开输入配置综合与布局布线：Logic20668、FF8066、BSRAM94/118、DSP16/118。Setup/Hold/Recovery/Removal/最小脉宽最差余量依次+0.184/+0.131/+0.834/+0.143/+5.803ns；34个引脚、17项有效约束及12个复位布局落点核验通过，未改引脚／SDC／process配置。

首次新联合测试在最后复位阶段错误沿用了累计帧计数，误把复位首帧计为持续欠载；按已有上电窗口合同改为每次复位独立计数，最终重跑通过。只修正本轮新TB，不改RTL或放宽稳态欠载检查。供应商仿真库的4项real_duty自触发提示保留，不作为本设计功能错误或已解决事项。

位流（仅预览控件／原有演奏）：`build/audition/touch_brightness_prepare_20261017/hdmi_touch_brightness_preview.fs`。
SHA256：`93eae4d1294394a11e1ca9f599ff4ff9b9850b2f3941b47848078748d3614658`。
本包不包含可用USB接收；输入常量会被综合裁剪，接入动态主机后需重新实现与审查资源／时序。当前+0.184ns是本次约束下最差Setup余量，不称宽裕或全面签核。旧PR1014、DAC完整外部时序、HDMI板外预算、真实触摸和模拟总延迟仍未闭合；没有代为烧录或推送。

详见[交接合同](touch-brightness.md)与 `verification/evidence/touch/summary.json`。可重复汇总命令：`python verification/scripts/check_touch_preparation.py --package`。旧 `octave3_j13_20261017` 包保持原样。

## 高云并行布局布线试跑脚本

入口为`projects/hdmi/sweep_pnr.ps1`。高云任务由同目录`pnr_trial.tcl`执行，Python标准库调度器`verification/scripts/pnr_sweep.py`负责独立目录、并发进程、验收和排名；无需新增依赖。目标是当前60K/31005的正式HDMI工程。

```powershell
# 默认五组策略，三路并行；最优配置再独立复跑一次。
./projects/hdmi/sweep_pnr.ps1 -Jobs 3 -ConfirmBest

# 同时比较两种时钟布线顺序，共10组（包含原配置对照）。
./projects/hdmi/sweep_pnr.ps1 -Jobs 3 -ClockOrders 0,1 -ConfirmBest

# 如主要比较建立时间，显式选择setup排名；所有原验收门槛仍生效。
./projects/hdmi/sweep_pnr.ps1 -Jobs 3 -Rank setup -Rules '0:0','1:1','2:1','3:1','4:1'

# 只准备输入快照及验证组合，不启动综合或PNR。
./projects/hdmi/sweep_pnr.ps1 -PrepareOnly
```

参数`Rules`格式为“布局:布线”。选项依据本机随软件安装的[SUG1220-2.1E](<D:/Gowin/Gowin_V1.9.12.04_x64/IDE/doc/EN/SUG1220-2.1E_Gowin Software Tcl Commands User Guide.pdf>)印刷页36～42：

| 选项 | 可选值与含义 |
| --- | --- |
| `-place_option` | 0默认/速度优先，1可布通性，2时序优先，3和4尝试改善布局 |
| `-route_option` | 0默认，1更充分的布线优化，2速度优先 |
| `-clock_route_order` | 0按扇出从高到低，1按频率从高到低；针对非Clock原语生成的时钟线 |

默认组合为0:0、2:0、2:1、3:1、4:1，时钟顺序0。没有编造随机seed选项；算法试跑也不能修复缺失的外部时序模型。

每批输出到唯一`build/pnr_sweep/<时间_标识>/`，先复制输入、只综合一次，再将同一份VG网表分给各路`run pnr`。每路独立impl/日志/报告，源RTL、ROM、器件、引脚、SDC、复位定向位置及其余process选项固定。只允许改变上述三个工艺策略字段；脚本校验实际生效process、相同网表哈希和批次前后源文件身份。正式`process_config.json`及`projects/hdmi/impl`不会被覆盖。

每路复用原HDMI检查器：34实际引脚、17条约束、12个复位落点、五类时序、位流与输入哈希。五类余量均非负，恢复/移除仍须≥0.100ns；失败、缺报告或校验异常的候选不进入最优集合。默认`balanced`优先最大化五类中的最小余量，同分再比较setup、hold；`setup`模式先比较最差setup，仍不能跳过其他验收。所有候选与失败原因均保留，不只报赢家。

结果入口：`results.csv`/`results.json`为完整排行榜，`runs/*/result.json`对应各路结果，`best/piano_hdmi.fs`为选定候选，`best/winner.json`记录策略、基线、共同网表及复跑对照。`-ConfirmBest`结果另存`confirmation.json`；repeat_matches比较五类余量和资源，不要求FS字节相同。2026-10-17修正发布门槛后，要求确认时，确认失败/缺失/越过时序门槛会非零退出且不发布best，原试跑报告照常保留；缺产物、位流变化、源码变化也会拒绝发布。位流均未代为下载，不自动晋升成正式配置。

并发数范围1～8、默认3，每路超时默认30分钟；超时只终止该路派生进程树。本机可用内存核对后实际采用三路。并行许可不足时，失败日志会被保留，可改`-Jobs 1`；不会静默改成其他约束或降低时序门槛。

调度器验证入口：`python verification/scripts/test_pnr_sweep.py`，覆盖策略合法性、原配置对照、三字段白名单、快照隔离/越界拒绝、失败淘汰、五类余量/复位门槛、两种排名、CSV形状及子进程失败传播。

### 2026-10-17 实际试跑结果

在源版本`922e059`上执行默认五组、三路并发、一次共同综合及赢家独立复跑。7项调度器单元测试通过。以下单位均为ns，五组均通过原HDMI检查；表按默认综合排名排列，不只比较setup。

| 布局/布线/时钟顺序 | setup | hold | recovery | removal | pulse-width | 五类最小值 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **4/1/0** | **1.421** | **0.187** | **0.976** | **0.144** | **6.072** | **0.144** |
| 0/0/0，原配置 | 1.303 | 0.124 | 0.834 | 0.143 | 5.803 | 0.124 |
| 3/1/0 | 2.663 | 0.049 | 0.976 | 0.144 | 5.803 | 0.049 |
| 2/1/0 | 1.598 | 0.048 | 0.976 | 0.144 | 5.803 | 0.048 |
| 2/0/0 | 0.548 | 0.046 | 0.834 | 0.143 | 5.803 | 0.046 |

布局3虽然setup最高，但hold降至49ps，因此没有按默认规则选中。布局4/布线1的五项余量均优于原配置；Logic由20704增至20708，寄存器8059、BSRAM94、DSP13.5、PLLA1不变。该配置独立PNR复跑也通过检查，五项余量及资源完全一致，`repeat_matches=true`。两次FS哈希不同，不据此声称字节级复现。

完整日志、输入快照、共同VG及排名保留在`build/pnr_sweep/20261017_202052_9cf8e1/`，精简审计记录见[summary.json](../verification/evidence/pnr_sweep/summary.json)。候选为该目录`best/piano_hdmi.fs`，SHA256 `d2d55efc507de897a56c4373446a2c50f6f59298278de0a1725d541074f8b736`；确认轮FS为`6c4aa3b1a4207143e917084cfd1e13d8f1e750adacb4992e83597c67ebea5e25`。正式工程原FS仍是`23b8d73c5ae0049b9f55db50dc75144a82c7b2fab65e02652ae2a5fe537063f8`，原process与全部试跑输入身份检查不变。

本轮未改RTL或TB，因此未重复功能仿真；只验证新增调度器和同逻辑的实现策略。未自动覆盖正式工程配置/位流，未烧录、未推送。最薄余量仍只有144ps，PR1014、DAC完整外部时序及板外HDMI预算仍未闭合；这些结果不是整机延迟测量或全面时序签核。

## 2026-10-17 无损架构优化（当前结果）

用户确认按资源/时序优先实施。对照基线为Git `922e059d14fdf09c07c80f3562ffd678fd23dac8`及修改前报告；当前工作区包含未提交改动，源码身份和全部结果以[architecture/summary.json](../verification/evidence/architecture/summary.json)为准。队友TB、原始黄金数据、引脚、SDC、复位定向布局、正式process配置与用户`.vscode/config.json`均保留原样，165份既有输入逐一核对。

### 改动与审查结论

| 类型/等级 | 定位 | 原因与处理 |
| --- | --- | --- |
| 功能错误，Medium | `rtl/top/piano_hdmi_top.v:49` | 复位显示8而音频实际单位增益65536；显示改为127，真实启动音频增益不变。两入口ADC参数显式对齐。 |
| 验证门槛错误，Medium | `verification/scripts/pnr_sweep.py:195` | 要求最佳候选复跑时，失败仍会发布best；现在确认失败/缺产物/源文件变化/位流变化均拒绝发布，全部文件复制成功才发布目录。 |
| 存储组织，优化 | `rtl/synth/modal_parameter_rom.v:6` | 每音64槽仅使用48项；保留规范参数表，派生三个4096深度bank。bank内地址直接拼接，无地址乘法，读延迟仍一拍。 |
| 像素组合逻辑，优化 | `rtl/display/instrument_panel_ui.v:112` | 九种倍率直接查BCD/字数，代替通用移位加三十进制转换。界面布局、覆盖度字模与像素流水延迟不变。 |

参数表仍包含两音色和全部128个MIDI音号；只去除从未调度的48～63槽的硬件存储。原始`.mem`和生成公式不变，三个派生文件不是另一版音色。`model/pack_modal_rom.py --write`可重生；三个工程的Tcl入口逐字校验原表与bank，过期/缺失即失败。实际模态参数pROM由71块降至49块；状态RAM与其他公式保持。A核心只有访存连接调整，精确来源/当前哈希在`verification/data/upstream_modifications.json`，不重写原导入来源哈希。

本轮主观可维护性评价8/10：新边界集中在ROM读接口，主链路可继续逐拍对照；外部时序、USB触摸和实物验收仍是独立未完成项，该评价不是比赛分数或签核。

### 资源与五类余量

| 指标 | 修改前HDMI原配置 | 当前HDMI原配置0/0/0 | 当前推荐2/1/0 | 当前无屏原配置 |
| --- | ---: | ---: | ---: | ---: |
| Logic | 20704 | 20653 | 20657 | 16561 |
| Register | 8059 | 8059 | 8059 | 7374 |
| BSRAM/118 | 94 | 72 | 72 | 58 |
| DSP | 13.5 | 13.5 | 13.5 | 13 |
| Setup/ns | 1.303 | 0.033 | 3.578 | 2.220 |
| Hold/ns | 0.124 | 0.247 | 0.212 | 0.247 |
| Recovery/ns | 0.834 | 0.832 | 0.976 | 16.256 |
| Removal/ns | 0.143 | 0.143 | 0.144 | 0.580 |
| Pulse/ns | 5.803 | 5.803 | 5.803 | 6.809 |

两入口各回收22块BSRAM，带屏约由80%降至61%（Gowin表向上显示62%）。无屏原资源为Logic16127/FF7110/BSRAM80/DSP13；新Logic与FF略增，Removal由1.220降至0.580ns，其余原约束检查通过。没有声称所有资源/余量同时改善。

同一优化后网表的五组PNR全部通过既有检查，以下单位ns：

| 布局/布线/时钟顺序 | Setup | Hold | Recovery | Removal | Pulse |
| --- | ---: | ---: | ---: | ---: | ---: |
| **2/1/0** | **3.578** | **0.212** | **0.976** | **0.144** | **5.803** |
| 4/1/0 | 2.071 | 0.183 | 0.976 | 0.144 | 6.072 |
| 2/0/0 | 2.625 | 0.226 | 0.751 | 0.143 | 5.803 |
| 3/1/0 | 2.791 | 0.139 | 0.976 | 0.144 | 5.803 |
| 0/0/0 | 0.033 | 0.247 | 0.832 | 0.143 | 5.803 |

默认balanced选择2/1/0，独立PNR确认轮余量/资源相同，`repeat_matches=true`。与修改前同一2/1/0策略相比，Setup从1.598至3.578ns、Hold从0.048至0.212ns；与修改前正式0/0/0相比，推荐候选五项均不低。默认0/0/0虽然非负，Setup仅33ps，不作为本轮推荐下载。正式process仍保持原配置，候选单独存放，没有将其资源/时序冒充默认impl的结果。带屏34引脚/17约束/12个复位落点及两入口J13接线、引脚/电压负向检查均通过。

### 数字验证与旧测试合同

- 171个文件以`-vlog01compat -pedanticerrors`严格编译，不用SystemVerilog；参数ROM16522项检查覆盖全部16384逻辑地址、128音号/两预设、读使能、复位和静音填充，地址故障注入被拒绝。
- 固定Git原核心仅在build临时还原，与当前核心每拍比较公开状态及4859个样本，含全部音号/两预设、满16声部、尾音、重触发、音量/弯音、忙时请求与复位。R923有效、R924缓存及60半边沿提前量保持；没有常驻第二套参考RTL。
- 倍率区域139264个像素请求与原渲染器相同，覆盖两模式、九档倍率与七个越界值；完整双界面1841400像素输出和当前波形测试通过。当前正式HDMI另在满16声部、HPD拔屏、PLL失锁、像素停钟和模式切换时检查374个音频样本及逐拍引脚输出，与无屏入口一致，停钟期间16次显示副本丢弃未反压音频。
- 队友原7项音色回归通过，独立整数模型11400个4/16声部样本及7500个控制样本对照通过；当前正式音区/真实ADC联调检查21190个DAC字，HDMI与无屏3307样本相同；旧控制合同显式兼容检查20642个DAC字。
- 包络独立整数139069项、HDMI17次恢复/2189个连续视频字及恢复后损坏负向检查通过。ROM生成器2项、布局调度/发布10项单元测试通过。

旧`tb_final_hdmi_isolation`在第64行固定要求启动显示8，修复显示后明确报`FAIL final display startup gain`。文件与断言原样保留，摘要将其列为旧合同不兼容，不把它算作当前通过项。正确启动及满16声部/拔屏/失锁/停钟的正式音频隔离由`tb_architecture_startup`检查；三音区由`tb_hdmi_octaves`、17次连续视频恢复由专项覆盖。截止期检查沿用既有四帧启动资格，随后逐拍检查。旧`audit_final.py`是10月16日合同的汇总，不作为本轮入口；使用下面的新审计命令。

```powershell
python verification/scripts/audit_architecture.py --sweep build/pnr_sweep/20261017_210227_e84131
```

### 下载身份与剩余边界

推荐带屏位流：`build/pnr_sweep/20261017_210227_e84131/best/piano_hdmi.fs`，SHA256 `d6bf9c0f0e25e1851cc00c663cf7e62e4f0af4314f63c4328be7501e025c1639`。确认轮FS为`2fa525750d1f370238fe6304f72f064be3b036c8491f049932097bc2d930b5a3`；两份有各自身份，不宣称字节一致。

默认带屏impl：`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 `e351636118686c4bc156da638873ef1c553a37a0996aa2e1d5d942d8de7104cf`，对应0.033ns Setup。无屏：`projects/piano/impl/pnr/piano_performance.fs`，SHA256 `f802797e23172f88cf10abfc445f84972b654550ee708a0a1c8f902d0b141690`。

未烧录、未推送、未做真实听感/模拟总延迟验收。PR1014、DAC完整外部时序和HDMI板外电气预算仍未闭合；USB主机/HID/正式触摸尚未接入，不能据BSRAM空余宣称相关功能已完成。

## 2026-10-18 单入口与局部路径优化

用户确认不再维护无屏项目，正式交付只用`projects/hdmi/piano_hdmi.gprj`。保留`piano_performance_top`作无显示仿真对照、A试听/C独立工程及队友TB；未删除有共享工具及既有未提交改动的`projects/piano/`。本轮最早的无屏实现发生在用户更新范围之前，仅作历史实验，不是新交付要求。没有大规模移动源码或把清晰的职责层合并成一个大模块。

### 审查与修改

| 等级 | 位置 | 发现与处理 |
|---|---|---|
| Medium（已处理） | `rtl/audio/sample_tick.v:47` | 高扇出节拍使能原先串过加法和比较；改为数学等价的余量阈值比较，正式相位计数32→26位、半边沿索引16→6位，不新增等待拍 |
| Low（已处理） | `rtl/audio/i2s_tx.v:45` | 16位计数器只数16个时隙位；按参数缩为4位，保持同拍样本、帧边界和欠载规则 |
| Medium（已处理） | `rtl/control/event_encoder.v:68` | 动态数组下标经过加法/回绕再选择；改为固定下标的全局首项/指针后首项选择，轮转次序、背压、溢出、旧音释放均不变 |
| Medium（已处理） | `rtl/display/instrument_panel_ui.v:112`、`:393` | 倍率控制字数会进入字框乘法、比较和文本覆盖链；改成固定四字槽，最终综合省半块DSP，不改变像素或流水级 |
| Medium（未闭合） | 本轮候选Hold表第1项 | `envelope_address_7_s1→波形RAM ADB[12]`仅0.116ns，低于上轮0.212ns；后续应单独评估RAM地址寄存器的定向布局/合法保持修复，不插RTL延时、不放宽约束 |
| High（既有验收缺口） | DAC/HDMI板外时序、PR1014与实物记录 | 内部约束通过不能覆盖外部预算和整机模拟延迟；本轮未改变这些约束，也未宣称全面签核 |

局部代码可维护性主观评分8/10：职责和独立回归较清楚，仍有兼容包装和历史工具路径。该评分不是时序签核或比赛完成度。本次没有发现所测路径中的功能不等价；不把这些局部测试表述为全项目穷尽证明。

### 实际资源与时序

基线是本轮开始时的工作区，**已包含上一轮ROM重排和启动显示修复**，不是仅以Git HEAD代替。目标为GW5AT-LV60PG484AC1/I0、Version B，工具Gowin1.9.12.04；50MHz系统/49MHz像素/245MHz串行。原接线、SDC/时序例外、process及12个复位定向落点不变。

| 指标 | 修改前默认布局 | 修改后默认布局 | 上轮最佳候选2/1 | 本轮平衡候选2/0 |
|---|---:|---:|---:|---:|
| Logic | 20653 | 20513 | 20657 | 20512 |
| 寄存器 | 8059 | 8030 | 8059 | 8030 |
| BSRAM | 72 | 72 | 72 | 72 |
| DSP | 13.5 | 13 | 13.5 | 13 |
| Setup/ns | 0.033 | 0.063 | 3.578 | 2.990 |
| Hold/ns | 0.247 | 0.179 | 0.212 | 0.116 |
| Recovery/ns | 0.832 | 0.832 | 0.976 | 0.834 |
| Removal/ns | 0.143 | 0.143 | 0.144 | 0.143 |
| 脉宽/ns | 5.803 | 5.803 | 5.803 | 5.803 |

本轮三个实际布局候选为0/0、2/0、2/1（时钟布线顺序均0）；2/1的Setup最高4.859ns，但Hold为0.114ns。工具按“五类最薄余量优先，再比较Setup/Hold”的既定规则选2/0，独立复跑资源和五类余量一致。**省资源已证实，但相对上轮最佳候选并未全面改善时序**；不把2/1的Setup和2/0的Hold拼成一份不存在的结果。前轮94→72块BSRAM的收益保留，不重复计成本轮新增收益。

中间试验也保留在`build/`：仅改音频计数/阈值时布局收益不稳定；加入事件选择后默认Logic20381、Setup0.148ns，仍被倍率字库路径限制；最后改固定字槽后该显示路径退出最慢路径列表。早期`20261018_180508_6fb203`批次中断，不是发布候选；`20261018_181522_e923fd`是未含最终字槽修改的中间批次，不能下载后当成本轮结果。

### 验证范围与身份

- 173份文件严格Verilog-2001编译；169份既有TB/上游/板级约束/process/用户配置哈希不变。本轮只改4份RTL，无SystemVerilog、无新时钟和新时序例外。
- 音频12组参数×300000周期，共360万拍逐拍差分；覆盖独立余数模型、异步复位、满速、最大位宽、DAC帧边界/同拍冲突/欠载。阈值偏一和串行位序偏一故障均被拒绝。
- 键事件1/2/13/16键配置共48万周期差分，覆盖回绕、背压、溢出、音区和持音；轮询优先级故障被拒绝。
- 倍率139264次像素请求与固定Git原版精确一致，含两音色、全部16个倍率输入；完整UI帧1841400有效像素检查通过。
- 原A的7项测试、11400点独立Python定点参考、原C的7项控制测试、139069次独立包络整数对照、正式R924音区/ADC/16声部与HDMI隔离、17次HDMI恢复及恢复后故障注入通过。音频/事件测试只依赖未再变化的三个模块；最终界面修改后重跑严格编译、正式集成、A回归和HDMI恢复，审计再次核对各输入清单。
- 3个布局候选及选中候选复跑通过现有34端口/17约束检查。没有重新跑手机/PC软件测试，因为本轮未修改其代码；旧结果不冒充本轮重测。

当前源码对应的验证候选：`build/pnr_sweep/20261018_182819_559cb1/best/piano_hdmi.fs`，SHA256 `93a99df1b30383ac7b60c2129952cdf41aad8c4cf9d256501a2188d5501c3c5a`。复跑FS为`f50ffd0c15a2fde28870a316018f316357fa56184fb596a5492406f73143e201`，报告一致但文件哈希不同，不宣称逐字节一致。

普通工程默认位流`projects/hdmi/impl/pnr/piano_hdmi.fs`的SHA256为`1e2ecf22564ccd73eb3330ffd79d8e1caa20f6679bd1fcc82a859ce8a04bb834`，对应Setup0.063ns，不能拿候选2.990ns描述它。没有将候选策略覆写到原process，也未自动烧录或推送。

本地审计及冻结基线/完整输入哈希见[摘要](../verification/evidence/datapath/summary.json)。复核命令：

```powershell
python verification/scripts/audit_audio_timing.py --sweep build/pnr_sweep/20261018_182819_559cb1
```

该审计依赖本轮`build/`内的改动前快照和原始日志；新克隆应重新运行测试/构建，不能用修改后的报告冒充旧基线。新源码的独立差分测试参考固定Git `922e059`，临时参考只写入build。USB触摸仍未正式接入，真实听感、线束/旋钮与模拟总延迟仍待实物验收。

## 2026-10-20 DAC数字边界与外部预算检查

用户批准先验证再决定是否改输出逻辑。本轮没有复现需要修改RTL的输出边界违例，因此只补独立测试和自动审计，未改发声逻辑、R923/R924合同、采样率、引脚、SDC、process及队友TB。开始时记录的289份既有RTL/板级/工程/测试/上游/用户配置文件哈希均未变化；该范围只新增一份独立TB，不包含文档与新增检查脚本。

### 新增内容与实际结果

- `verification/tb/audio/tb_dac_launch_timing.v`：从公开接口检查真实`synth_top`，使用独立帧缓存参考；检查BCK短长半周期、帧周期、右/左声道、MSB位序、DIN/WS仅在BCK下降沿更新、欠载与复位恢复。5次启动/复位阶段、1536个采样上升沿、50帧、13个欠载帧通过，DIN和WS最短数字建立/保持窗口均为320ns。异步复位可截断时钟，不能把稳态窗口结论用于复位瞬间。
- 故障注入分别令观测DIN、WS在BCK接收上升沿翻转，两者均被预期检查拒绝。初次负向调用因ModelSim绝对库路径解析失败，改用既有测试器的相对库路径后重跑成功；工具启动失败不计作故障检出。
- `verification/data/dac_timing_contract.json`：记录器件来源、已知规格和缺失参数；未知值保持`null`，不使用零代替。
- `verification/scripts/check_dac_timing.py`：核对85份本次仿真输入、81份既有默认HDMI构建输入、位流/报告身份、原局部0～20ns约束及负向日志；提取BCK/WS/DIN已打印的最大/最小路径。5项Python自检通过，包含未知值传播、预算边界、非法参数、缺失/损坏报告及负余量拒绝。
- 174份文件通过严格Verilog-2001编译；未改动的`synth_top_tb`、`tb_audio_boundaries`、`tb_hdmi_octaves`重跑通过，后者包含3307个一致音频样本。旧边界测试中的兼容R4用例不作为正式R924延迟证据。

### 为什么仍不能称为外部时序闭合

[PT8211 V1.7官方资料](https://www.princeton.com.tw/Portals/0/activeforums_Attach/PT8211%20V1.7_E.pdf)给出时钟高电平时间和边沿时间等指标，但没有单列DIN/WS建立、保持时间。其`tH=25ns`是时钟高电平持续时间，不是数据保持时间。当前接收格式为右对齐LSBJ，不把它与标准Philips I2S混称。

320ns仅为50MHz名义时钟下的零延迟数字仿真窗口。在全部发送端到引脚延迟均满足原0～20ns窗口的假设下，可以先得到300ns的临时窗口，再扣板级偏斜、时钟不确定度和接收要求；它**不是已验证的外部Slack**。现有报告每个端口只打印部分边沿路径，不能当作全部上升/下降沿和工况覆盖。

仍需补齐：厂商DIN/WS接收要求、31005走线偏斜与时钟误差、所有相关边沿/工况路径、DAC引脚电压/负载/上升下降时间，以及复位期间模拟输出瞬态。审计当前状态固定为`INCOMPLETE_EXTERNAL_EVIDENCE`、`signoff=false`；即使后续手填参数令算术余量为正，也不能跳过这些证据。

### 复现及交付边界

```powershell
./verification/scripts/check_verilog.ps1
python verification/scripts/check_dac_timing.py --self-test
python verification/scripts/check_dac_timing.py --run --allow-incomplete
python verification/scripts/check_dac_timing.py
```

本机使用ModelSim 10.6e（`C:/Library/modelsim/win64`）；新环境应按脚本`--help`设置实际工具路径。最后一条在证据缺失时返回退出码2，这是预期的阻止签核行为；`--allow-incomplete`只允许收集摘要，不能把未闭合变成通过。摘要与日志生成于`build/regression/dac_timing/`，新克隆需先重建当前HDMI工程并运行测试，不能只复制旧摘要。

本轮没有重新综合/布局布线，没有改变默认位流SHA256 `1e2ecf22564ccd73eb3330ffd79d8e1caa20f6679bd1fcc82a859ce8a04bb834`；未烧录、未推送、未测真实DAC波形和整机模拟延迟。PR1014及其他既有外部时序缺口不因本次数字测试自动消除。

## 2026-10-22 五黑键引脚迁移与Git只读同步

按用户确认，五黑键C#/D#/F#/G#/A#改用C18/E19/D20/F15/F16（J13-40/38/36/34/32）。旧B16/B15/A16/A15/A20分配作废；八白键、ADC及其他端口不变。31005底板第19页J13→第7页BTB→60K核心板球位/Bank，另与Gowin PBGA484A器件表交叉核对；不是将138K Bank直接照搬。蓝牙RXD/TXD/STATE仅预留B16/B15/A16，未新增RTL端口，不声称能通信。

### 本轮实际验证

- 174文件严格Verilog-2001检查通过，不使用SV模式；受保护的RTL/ROM/全部现有TB、上游代码、SDC/HDMI约束/process和用户编辑器配置共220文件与本轮起点SHA256一致。
- 原样运行`tb_piano_13_keys`、`tb_piano_13_debounce`、`tb_performance_octaves`及`tb_hdmi_octaves`通过；其中三音区双音色覆盖78音/满16声部/旧音松键/真实ADC模型/R924及21190个DAC字，HDMI对照3307个音频样本。没有修改队友TB，也没有宣称所有历史测试全部重跑。
- 接线检查验证CST、接线文档、器件包、实际PNR报告中的15路琴键/ADC位置、电压和方向；另拒绝错引脚、恢复旧黑键引脚、错电压、错实际报告4类故障。
- Gowin1.9.12.04按原process重新综合/布局布线；34个实际端口、17项有效SDC约束、12个HDMI复位原语位置及输入/位流身份检查通过。未放宽时序约束。

| 项目 | 当前接线版 |
|---|---|
| 下载文件 | `projects/hdmi/impl/pnr/piano_hdmi.fs` |
| SHA256 | `c21fd1b86a3a80293a2307d27a2f6b9db9c46a86a6ec2fe2299c8ede7cc4c6ae` |
| Logic / Register / BSRAM / DSP | 20513 / 8030 / 72 / 13 |
| Setup / Hold / Recovery / Removal / Pulse余量ns | +0.063 / +0.179 / +0.832 / +0.143 / +5.803 |

建立余量仅63ps，不能称时序宽裕。数字实现仅通过当前约束，不等于DAC完整外部时序、HDMI电气和实物总延迟签核。音频仍R923有效/R924缓存；旧布局候选及队友效果器位流不能配本次接线。本轮未下载、未改实际接线、未测听感/延迟。

机器可读记录：`build/pin_migration_20261022/summary.json`及`protected_inputs.json`；实现证据`build/hdmi/implementation_check.json`，原始报告`projects/hdmi/impl/pnr/piano_hdmi.rpt.txt`，功能日志在`build/regression/keyboard/`及`build/regression/final/`。此前默认位流和报告留在`build/pin_migration_20261022/prior_default/`仅用于对照，不是下载推荐或源码旧版副本。

```powershell
./verification/scripts/check_verilog.ps1
./verification/scripts/run_keyboard_tests.ps1 -ModelSimBin C:/Library/modelsim/win64
python verification/scripts/run_final_tests.py tb_performance_octaves tb_hdmi_octaves
./projects/hdmi/build.ps1
python verification/scripts/check_j13_wiring.py --report projects/hdmi/impl/pnr/piano_hdmi.rpt.txt --device-json D:/Gowin/Gowin_V1.9.12.04_x64/IDE/data/device/GW5AT-60B/PBGA484A.json --negative-control --output build/pin_migration_20261022/summary.json
```

### Git与远端效果器边界

已fetch，origin/master到e06e344、origin/cleanup/expression-brightness到f314bc0；本地HEAD仍922e059，相对origin/master提交计数ahead3/behind2。用户明确选择“先只拉取，暂不提交或合并”，本轮没有commit/merge/push，也未更改Git身份或覆盖本地优化。

队友效果器分支已有room_reverb/echo_delay/chorus_effect及试听构建，属于“远端已有、当前主工程未集成”。其HDMI缓存合同R953、报告BSRAM114/118是队友分支的配置，不是本次72块BSRAM的结果；不能简单相加减推算整合资源，也不能把其测试记录当作本机已重跑。后续获准整合时须保留现有ROM重排、接线和音频时刻检查，重新验证干声/湿声/尾音/欠载及PNR。

## 2026-10-23 按约束、RTL、综合、实现顺序改善时序

本节记录当前含Chorus/Delay/Room的唯一正式HDMI工程，取代上文旧接线版及“尚未整合效果器”的当前状态描述；历史结果保持原貌。用户批准本地执行优化，不推送、不烧录。

### 诊断与方法来源

- 约束：保留原50MHz系统、49MHz像素、245MHz串行的关系、17项现有SDC、34个端口及12个HDMI复位布局约束。最差Setup为复位释放/采样使能经过包络选择链，8级逻辑、83.539%数据路径延迟来自布线；最差Hold为波形RAM地址寄存器到RAM，含0.170ns时钟偏斜。Setup和Hold分别评估。
- RTL：实验将包络事件直接解码为起音/释放/衰减首拍，预先计算常量计数减一，保持数值和采样时刻。独立整数参考139069次、旧实现逐拍全状态对照750000次通过；起音故障在第3拍被拒绝。此候选没有取得最好的整体余量，正式`instrument_env.v`保持原字节。实验源码只存`build/timing_order_20261023/`，不新增正式旧版模块。
- 综合：检查推断及扇出，保持原RAM/DSP类型、数值位宽和音频流水线。没有为提高时序缩短尾音、降低精度或变更音色模型。
- 实现：使用[高云SUG113第4章](https://cdn.gowinsemi.com.cn/SUG113E.pdf)的高扇出资源复制与实现策略；本机SUG1220-2.1E第39～42印刷页核对选项。正式`Replicate_Resources=true`、`Place_Option=4`、`Route_Option=1`、`Clock_Route_Order=0`。工具导出`build/hdmi/effective_options.tcl`证明实际采用值；没有启用retiming。复制涉及多个控制/数据网络，并没有消除高扇出的全局复位。

同时研究[verilog-axis树形优先编码](https://github.com/alexforencich/verilog-axis/blob/master/rtl/priority_encoder.v)及[ZipCPU分级乘加](https://github.com/ZipCPU/dspfilters/blob/master/rtl/firtap.v)。它们作为结构思路参考，本轮未导入第三方代码，也没有在非关键算术路径增加流水级。

### 同条件对照与选择

| 候选 | Setup ns | Hold ns | Logic | FF | 结论 |
| --- | ---: | ---: | ---: | ---: | --- |
| 当前源码、原0/0/0配置重建 | 0.121 | 0.070 | 23321 | 9250 | 基线复现 |
| 原RTL＋资源复制，0/0/0 | 2.326 | 0.047 | 23318 | 9443 | Hold退步，淘汰 |
| 并行包络，0/0/0 | 0.026 | 0.188 | 23067 | 9250 | Setup退步，淘汰 |
| 原RTL＋资源复制，2/1/0 | 5.077 | 0.048 | 23317 | 9443 | Hold退步，淘汰 |
| 原RTL＋资源复制，4/1/0 | 1.966 | 0.170 | 23317 | 9443 | 最薄余量最佳，采纳 |
| 并行包络，2/1/0 | 3.247 | 0.049 | 23069 | 9250 | Hold退步，淘汰 |
| 并行包络＋资源复制，0/0/0 | 0.216 | 0.115 | 23070 | 9444 | 合格，最薄余量较低 |
| 并行包络，4/1/0 | 0.765 | 0.083 | 23063 | 9250 | 合格，最薄余量较低 |
| 并行包络＋资源复制，4/1/0 | 0.731 | 0.050 | 23061 | 9444 | Hold退步，淘汰 |

各行均由本轮工具执行，原默认基线重新综合/实现；固定网表的PNR候选核对网表哈希及禁用RTL的输入工程。最初三次PNR完成后因未打印`Skip synthesis`被脚本误拒绝，原失败记录保留；实际日志明确直接读取指定网表。检查器现改为核对唯一网表、禁用RTL、真实网表读取路径、没有启动综合及网表哈希，不能只凭可选日志短语判断。新增负向检查拒绝活跃RTL、错误网表和启动综合的日志，共14项脚本测试通过。

### 正式重建与功能证据

隔离候选和正式全量重建的资源、五类最差余量完全一致。正式工具为Gowin1.9.12.04，器件GW5AT-LV60PG484AC1/I0，Version B；Setup用Slow 0.93V 0°C，Hold用Fast 0.975V 85°C。

| 项目 | 基线 | 正式重建 |
| --- | ---: | ---: |
| Setup / Hold ns | 0.121 / 0.070 | 1.966 / 0.170 |
| Recovery / Removal ns | 0.834 / 0.143 | 0.976 / 0.144 |
| 最小脉宽余量 ns | 5.803 | 6.072 |
| Logic / FF | 23321 / 9250 | 23317 / 9443 |
| BSRAM / DSP | 92 / 24.5 | 92 / 24.5 |

本轮实际运行：187份严格Verilog-2001编译；`tb_effects_hdmi`（R953、13413个满16声部样本、27180个串行DAC字、两预设/三音区/旋钮、拔屏及失锁隔离、脏复位）；`tb_effects_pa`（92160个尾声有效周期、83620个尾声静音间隙、真实DAC帧排空后关功放）；`tb_final_modal_adapter`（4436样本、R923黄金数据、代次/释放/控制）；`tb_final_env_alignment`（139069次独立整数对照）。HDMI恢复17轮、四路2189视频字通过，恢复后通道损坏负向测试在epoch1被拒绝。源码布局检查76个有效模块、4份GPRJ通过。未把其余历史测试称为本轮重跑。

位流唯一入口`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 `b24d6796ed6b89164b48a985eda61b24a0b45fc97dedb7062b91aad37cc2b87e`。机器摘要`verification/evidence/timing_order/summary.json`；所有试验/失败及冻结前文件身份保留在`build/timing_order_20261023/`。正式RTL、原TB、ROM和CST/SDC均逐字节保持；只更新实现配置、实际选项导出及PNR日志核验。R923/R953、48kHz、16声部及现有接线不变。

内部报告通过仍不闭合PR1014通用时钟布线、完整DAC接收器外部时序、HDMI板外电气与真实整机延迟。此轮未下载、未实物试听、未提交或推送Git。
## 2026-10-23 滑条、蓝牙与屏幕导奏

用户追加范围：B10K实体滑条明亮度、独立HC-08手机链路；取消LED硬件，采用预置14音屏幕导奏。既有RTL/TB/ROM以本轮开始的工作区哈希为基线，不用HEAD冒充本轮脏工作区。未提交、未推送、未烧录。

### 实现边界

- AIN0/1仍音量/弯音；AIN2独立7位明亮度，不扩大原14位旋钮总线，不增加音频流水拍数。三路轮询每个旋钮结果及时发布，关闭第三路则保留旧成对发布。未就绪/总线故障回127；不能检测悬空滑条。裸件的具体端子待照片或测量，识别法在接线表；无滑条先固定AIN2=3.3V。
- BLE复制原协议解析器并独立收发：PC约115200，HC-08默认约9600；事件层三路轮询，不合并UART位流。9位source区分实体/PC/BLE，同音各自释放。STATE两级同步+时钟资格，断连保留独立取消请求，清手机gate但不截效果尾音。B16/B15/A16使用独立ble.cst/ble.sdc，原CST/SDC字节不变。
- 导奏只观察被接受的新起音，不发音、不反压。内置公版旋律《小星星》前14音，错误/松键/持有电平均不推进；完成后停止提示，KEY0复位重练。KEY1改变目标音区、KEY2不清进度。PC/BLE正确的新起音也可推进；不把静音槽或谐波当新增声部。
- 原子显示副本74→83位；青绿空心框=下一音，淡黄=实际持键，顶部“指示”与进度复用旧字形，无新字库/帧缓存。USB主机/HID未实现，不能点击屏幕演奏；也不自动认定官方明确LED项目达标。

### 已运行验证

`check_verilog.ps1`在本机嵌套PowerShell仍触发原生输出编码错误，使用直接ModelSim同参数替代，194份有效文件以`-vlog01compat -pedanticerrors`严格编译；不使用SV。全部既有TB未改，新测试单独保存：

| 测试 | 实际覆盖 |
|---|---|
| tb_slider_controls | 50MHz/48kHz与1.35ms转换模型；12个输入相位，最大参数稳定观测9,544,909ns；故障/恢复/ADC不中断的FPGA复位 |
| tb_ble_event_arbiter | 固定种子b10c，3000周期三路背压/队头稳定/顺序/轮询公平；采样边界分类取消 |
| tb_ble_link | 独立HELLO/回包，同音多来源，NOTE_OFF/PANIC，半行断连/重连、单路超时，模式与R953，674个音频样本 |
| tb_practice_guide | 三音区42个正确音，错音/持有/重复/完成/复位/切档 |
| tb_slider_guide_hdmi | 正式HDMI+真实三路I2C到低通；导奏、模式/音区、拔屏/复位；2298样本，与无显示参照逐拍比对DAC/PA/PC回包 |
| tb_practice_display | 两帧1,228,800个真实RGB像素，边框/普通持键独立颜色判定、83位原子帧；预览来自RTL输出而不是重画 |
| tb_review_knob_latency | 原双通道9相位/定时ADC/故障与复位兼容，文件未改 |
| 既有音频回归 | tb_effects_hdmi、tb_performance_system、tb_uart_instrument、tb_final_modal_adapter、tb_final_env_alignment原样通过；R923黄金样本与139069次整数对照 |
| HDMI恢复/流程 | 17个恢复epoch、10位相、2189个四路视频字；恢复后位序故障被拒；14项PNR工具测试通过 |

新负向测试：错误BLE取消掩码与“错键仍推进”均被测试拒绝；没有改正式源码制造假通过。数字参数9.545ms不含真实模拟RC/DAC/音箱，也不是穷举最坏上界；BLE UART位时间按比例加速用于协议仿真，不证明无线延迟。

### 实现状态与重现

最终含导奏HDMI完整PNR已通过现有约束检查，37个实际约束端口、21项活动约束（原17项＋独立BLE4项），原CST/SDC及process字节不变。670份既有保护文件未改，包括全部既有TB/上游快照、原ROM/音色核心、原约束及用户`.vscode`配置。只新增两份BLE约束，不把豁免新同步器原始异步输入说成放宽旧时序。

| 指标 | 最终实际报告 |
|---|---:|
| Logic | 26342 / 59904（约44%） |
| FF | 12038 / 60780 |
| BSRAM | 90 / 118（剩28块） |
| DSP | 25.5 / 118 |
| Setup / Hold | +2.302ns / +0.064ns |
| Recovery / Removal / Pulse | +0.976ns / +0.144ns / +6.072ns |

第一版导奏组合路径从BLE取消判定穿过事件仲裁进入导奏使能，且新增文字/几何拉长像素组合链；实际Setup=-0.935ns，未放行，文件已隔离为`build/slider_ble_20261023/failed_guide1/NOT_FOR_PROGRAMMING.fs`。修复只给导奏观察副本寄存（显示观察多20ns，音频不变）、把新标题区域独立选择、移除重复等音指位提示并保留吉他下方目标音名框、缩小分隔符几何运算；未改A或任何既有TB/约束。最终又统一重跑全部13项功能及三项负向回归，不能拿中间通过版本当最终源码验证。

当前正式下载文件仍为`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 **`0407a18f4f95c2120149d3051e465839285d4e71261e76e5a377f3f529351bc0`**；原始报告/清单与构建输出在`build/slider_ble_20261023/implementation_final_exact/`，摘要在`verification/evidence/slider_ble/summary.json`。两张预览来自完整真实RGB仿真帧：`build/slider_ble_20261023/guide_piano.png`、`guide_guitar.png`；测试没有送音频副本，预览中的波形为空不是功能缺失。

Hold最薄64ps，仍不能称时序宽裕或全面外部签核。原有PR1014、完整DAC外部时序、HDMI电气与整机模拟延迟、真实App联调、B10K具体脚位仍未验收；本轮没有推送或操作硬件。显示正常时提示可能到下一帧才可见，音频不等待此显示副本。

```powershell
python verification/scripts/run_final_tests.py tb_slider_controls tb_ble_event_arbiter tb_ble_link tb_practice_guide tb_slider_guide_hdmi tb_practice_display tb_review_knob_latency
python verification/scripts/run_final_tests.py tb_ble_event_arbiter --mutation BleCancel
python verification/scripts/run_final_tests.py tb_practice_guide --mutation GuideAdvance
python verification/scripts/run_final_tests.py tb_review_hdmi_reset_recovery
python verification/scripts/run_final_tests.py tb_review_hdmi_reset_recovery --mutation HdmiRecovery
./projects/hdmi/build.ps1
python verification/scripts/check_j13_wiring.py --report projects/hdmi/impl/pnr/piano_hdmi.rpt.txt --negative-control
```

## 2026-10-23 最薄余量优先的正式实现

本节取代上节64ps版本作为当前正式身份；上节导奏等功能及其验证是当时快照。唯一入口仍为`projects/hdmi/piano_hdmi.gprj`，下载文件仍为`projects/hdmi/impl/pnr/piano_hdmi.fs`。本轮没有提交、推送或操作硬件。

### 决策和试验边界

最薄路径是混响写数据/地址寄存器到BSRAM：原最差`w1_17_s0/Q`→`mem1_mem1_0_1_s/DI[8]`，快角时钟偏斜0.177ns，数据延迟约0.274ns，Hold仅0.064ns。工具已启用保持修复，当前为正不代表还有足够工程余量；本轮没有降低时钟或改时序例外。

冻结当前脏工作区与已验证综合网表，比较未改基线、四组六FF局部布局及四组规则，共9组。所有原RTL/ROM/TB/CST/SDC保持，局部位置约束只写build副本。出现CT1094/NULL网格的两组即使五类报告为正也拒绝；有效局部候选改善Hold却明显损失Setup，不进入正式工程。所有原始候选及拒绝记录保存在`build/timing_margin_20261023/`，不作为下载入口。

| 隔离规则/局部方案 | Setup ns | Hold ns | 决策 |
| --- | ---: | ---: | --- |
| 原Place4/Route1/ClockOrder0 | 2.302 | 0.064 | 独立复跑与原报告一致 |
| 六FF移至R36C69/70 | 0.435 | 0.133 | Setup下降过多，拒绝 |
| 六FF移至R38C69/70 | 2.202 | 0.066 | 位置未生效，拒绝 |
| 六FF移至R36C72/73 | 1.129 | 0.085 | 无均衡收益，拒绝 |
| 六FF移至R36C74/75 | 1.508 | 0.052 | NULL位置/未生效，拒绝 |
| Place4/Route0/ClockOrder0 | 0.021 | 0.064 | Setup太薄，拒绝 |
| Place4/Route2/ClockOrder0 | 3.135 | 0.062 | 最薄余量未改善，不选 |
| Place4/Route1/ClockOrder1 | 2.302 | 0.064 | 无收益，不选 |
| Place3/Route1/ClockOrder0 | 1.193 | 0.184 | 用户接受取舍后复跑、采用 |

初始筛选希望Setup≥1.5ns。候选P3/R1/C0没有达到这条工程筛选线；向用户完整展示Hold64→184ps、Setup2.302→1.193ns后，用户明确选择“优先改善最薄余量，复跑一致后采用Place=3”。这改变的是候选取舍，不是降低SDC要求或隐藏负余量。正式process仅`Place_Option`从4改3；Route=1、ClockOrder=0、资源复制和其余选项不动，没有加入任何局部位置约束。

### 复跑及正式全量重建

候选、独立同网表复跑、正式全量综合/PNR三者的资源和五类余量一致。Gowin1.9.12.04，器件GW5AT-LV60PG484AC1/I0、Version B；Setup为Slow0.93V/0°C，Hold为Fast0.975V/85°C。

| 指标 | 旧正式版本 | 新正式版本 |
| --- | ---: | ---: |
| Setup ns | 2.302 | 1.193 |
| Hold ns | 0.064 | 0.184 |
| Recovery ns | 0.976 | 0.879 |
| Removal ns | 0.144 | 0.144 |
| Pulse ns | 6.072 | 5.803 |
| 五类最薄余量 ns | 0.064 | 0.144 |
| Logic | 26342 | 26340 |
| FF / BSRAM / DSP | 12038 / 90 / 25.5 | 12038 / 90 / 25.5 |

当前最薄转为HDMI串行器复位Removal144ps，仍偏紧。Setup、Recovery和Pulse有所下降；不得称各类全面改善或时序宽裕。37个引脚和21项活动时序约束保持，原/合并CST及SDC逐字节相同，12个HDMI复位原语落点仍按原约束核对。

### 源码与功能身份

- 194份当前文件以`-vlog01compat -pedanticerrors`严格编译，零错误/警告。RTL、ROM、全部既有TB、原约束及`.vscode/config.json`不变；扣除获准process与本轮4份文档更新，699份已有文件保持原哈希。
- 本轮原样重跑`tb_practice_guide`（42音/三档/错键/持有/重复/完成/复位）、`tb_ble_link`（674样本及单路断连隔离）、`tb_slider_guide_hdmi`（三路真实I2C模型、2298样本DAC/PA/UART逐拍隔离）、`tb_review_hdmi_reset_recovery`（17轮/10位相/四路2189字）。没有把上节其余功能或故障注入称为本轮重跑。
- 14项PNR流程测试、6项引脚故障控制及源码布局检查通过。音频R923原始/R953缓存、48kHz、16声部、全部演奏功能和接线保持，不增加发声等待。
- 初次额外网表文本核验拒绝了重建：Gowin会将`voice_gate`等改为`voice_gate_Z`并重新编号内部网络。保留原始哈希和差异诊断，不把不同VG称为字节相同。后续保守核验在84模块内检查1900912对token、本地名称双射及子模块接口映射，保留原语类型、常量/位索引/字段/块注释属性/时间单位与逐连接检查；7类故意改错的反例均被拒。结论仅为本次生成结构网表的一致重命名，不是任意行为RTL的形式等价证明。

当前正式位流SHA256：`2702c933ebde3678f69bd7b61894a2c5f99923bacbb133ab49a5681e5efaba40`。机器摘要与原始报告在`verification/evidence/timing_margin/summary.json`及同目录；完整冻结输入、试验、独立复跑和原实现归档位于`build/timing_margin_20261023/`。正式实现当前配置已采用，不需要改接线。

PR1014通用时钟布线、完整DAC外部时序、HDMI板外电气、USB触摸、真实App/滑条联调及整机模拟延迟仍未验收。本轮内部时序改善不能代替整机≤10ms/≤5ms测量，未据此勾选实物条目。

## 2026-10-23 HDMI复位余量与外部时序复核

结论：本轮没有找到值得替换正式版本的局部布局，保留上一节Place3版本及其完整位流字节。三个候选均只在`build/hdmi_reset_margin_20261023/`内修改12条复位物理位置约束中的部分位置；没有改正式RTL、ROM、任何既有TB、引脚、SDC、时钟或process，也没有重新发布下载包。

### 为什么最薄，怎样对照

正式最薄路径是HDMI第0/1/3路`serializer_release_0_s0/Q`到`OSER10/RESET`的Removal（复位与时钟边沿间隔）144ps，而非音频乘加Setup。像素时钟下降沿与串行时钟下降沿存在同沿检查，报告中的最小数据路径约0.639ns、捕获相对发射时钟偏斜约0.324ns；单纯降低音频逻辑级数不会消除此短路径。其次是混响地址寄存器到BSRAM的Hold184ps。降低时钟频率也不是同沿Hold/Removal的直接解法。

使用同一份已综合VG、相同P3/R1/C0和其余process，只变局部位置。实验前冻结737份当前文件及正式位流，记录采用门槛：五类最小余量高于0.144ns、Setup至少1.0ns、Recovery至少0.5ns、全部原检查及实际位置通过；若满足，还必须独立复跑及正式全量重建。它是候选选择门槛，不是修改时序约束。

| 隔离试验 | Setup ns | Hold ns | Recovery ns | Removal ns | Pulse ns | 结论 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 原位置基线复跑 | 1.193 | 0.184 | 0.879 | 0.144 | 5.803 | 与正式一致，保留正式版本 |
| 仅合并LUT移动一行 | 0.003 | 0.188 | 0.870 | 0.276 | 5.803 | 复位改善，但UI字库地址Setup只剩3ps，拒绝 |
| 每路两FF和LUT整体从C134移到C133 | 0.902 | 0.195 | 0.950 | 0.147 | 5.803 | 最薄只增3ps，Setup低于门槛，拒绝 |
| 仅第一级FF移动一行 | 1.342 | 0.184 | 0.794 | 0.141 | 5.803 | 最短路径改到第二级FF，最薄反降，拒绝 |

四组都通过现有37引脚、21项活动时序和12个实际复位落点检查；“五类正余量”不等于满足本轮采用标准。资源均FF12038/BSRAM90/DSP25.5，Logic整体移列候选26339，其余26340。少一个Logic不能抵消最薄余量未改善的问题。

第一种布局虽然只指定4个LUT位置，也改变了其余逻辑的全局放置结果：最差Setup变成`u_display/x_d_3_s0/Q`到字库ROM地址，不能假设局部约束只影响局部。第三种把原最短支路移开后，第二级FF与LUT重新打包成同槽，形成0.636ns短路径；不是在同一条路径上再增加距离就能保证整体收益。连续三种定向试验均未达门槛后，停止继续盲试位置；没有以失败的候选覆盖正式成果。

初次试验准备时，Tcl生成CST的换行/中文注释编码与源文件不同，整段字节替换校验拒绝了两个尚未开始PNR的目录。随后只对12条ASCII `INS_LOC`逐行精确匹配，在新目录运行以上候选；这属于准备脚本校验，不计作时序试验通过。JSON配置在隔离目录重新序列化，按字段值核对相同；正式process原字节不变。

### PR1014：有全局网络，但仍存在非专用接入告警

高云实现报告明确列出`sys_clk_d → PRIMARY`，串行时钟同时使用HCLK。因此PR1014不能解释成“整个系统时钟都走普通数据线”。输入仍为已确认板级晶振引脚V22，报告功能标识EMCCLK，告警指向`sys_clk_d`的通用布线段；当前证据尚不足以对完整接入路线签核。

PRIMARY/LW都报告8/8，但表中还包含混响/合唱控制信号及显示commit，不代表设计存在16个独立功能时钟域，也不等于LUT容量耗尽。禁止通过`LOCAL_CLOCK`强制普通布线、随意换晶振引脚或删掉告警来声称修复。增加专用PLL涉及启动、失锁、跨域及约束模型变化，不能作为本轮挪动几个位置的等价替换直接合入。

本轮核对安装目录中的高云官方资料：UG304-1.3.8E（印刷页103—105，OSER10异步高有效复位、PCLK=FCLK/5）；SUG1541-1.0E（18—20，CLOCK_LOC/BUFG）；SUG937-1.1E（149—150，PR1014说明）；UG306-1.0.9E（3—10，GCLK/HCLK）。文档完整路径与SHA256记入本轮摘要，不以其他器件系列的复位经验替代本器件验证。

### 实际重跑与仍缺的证据

- 194份文件严格Verilog-2001编译，零错误/警告；全部既有TB未改。
- 原HDMI恢复TB：17轮、10个位相、2189个四路视频字通过；恢复后才破坏位序的负向样例在epoch=1被拒绝。
- 原DAC发射测试：5轮、1536个采样沿、50帧，其中13个欠载帧；DIN/WS错边沿故障分别被拒绝。数字发射窗口320ns；在现有0..20ns端口延迟假设下的300ns只是临时预算，**不是DAC外部时序余量**。
- 14项PNR流程测试、6项引脚故障检查通过。737份既有保护文件除AGENTS/PLAN/本验证文档3份说明外，其余734份哈希不变；所有正式输入及原位流保持。没有本轮正式全量重建、推送、烧录或实物测量。

DAC仍缺DIN/WS接收建立与保持参数、31005板上相对延迟、时钟误差/抖动、所有输出边沿及角点覆盖和DAC管脚实测上升/下降时间。资料中的`tH=25ns`是BCK高电平宽度，不得拿来冒充数据保持时间。脚本仍明确输出`INCOMPLETE_EXTERNAL_EVIDENCE`、`signoff=false`，不会把数字测试通过改写成板外签核完成。

进一步提升的优先方向是重新评审复位释放相位结构，以及像素区域预解码/分级选择，以减轻布局对长组合链的敏感性；这是下一轮隔离设计候选，尚未实现。必须保持四路位序、复位/失锁恢复、像素对应关系和音频R923/R953合同，再用相同约束验证，不能先承诺余量一定提高。

当前唯一正式位流仍为`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 **`2702c933ebde3678f69bd7b61894a2c5f99923bacbb133ab49a5681e5efaba40`**。本轮摘要、四组时序表、落点、测试日志及资料哈希见`verification/evidence/hdmi_reset_margin/summary.json`；冻结输入和未采用试验留在build，不是新的下载入口。现有正余量说明在当前模型/约束下通过，既不能据小正数断言必然不稳定，也不能据此保证完整实物工况。

## 2026-10-23 琴键坐标并行解码：资源减少，未晋升

用户批准的边界是只改`instrument_ui_map.v`：将同组互斥矩形的逐键覆盖改为并行比较和独热常量字段汇总，显式保留黑键覆盖白键。接口仍为12位无符号x/y及乐器选择、58位组合输出；无时钟/复位/新增流水级。控制按钮、琴键位置、图像、音频合同及全部约束保持。候选仅位于`build/ui_map_parallel_20261023/candidate/`，并未进入正式RTL。

先冻结当前756份文件和位流，固定采用条件：全部功能与现有实现检查通过、Setup严格优于1.193ns、五类全局最小余量不低于0.144ns；满足后才独立复跑及正式重建。本轮使用相同Gowin V1.9.12.04、器件GW5AT-LV60PG484AC1/I0 Version B、P3/R1/C0、资源复制选项。原版和候选均从RTL完整综合/布局布线，只有候选映射文件不同，原及合并CST/SDC/process保持相同。

| 指标 | 原版本轮重建 | 并行映射候选 |
| --- | ---: | ---: |
| Setup ns | 1.193 | 0.433 |
| Hold ns | 0.184 | 0.191 |
| Recovery ns | 0.879 | 0.976 |
| Removal ns | 0.144 | 0.144 |
| Pulse ns | 5.803 | 5.803 |
| Logic | 26340 | 26264 |
| FF | 12038 | 12034 |
| BSRAM / DSP | 90 / 25.5 | 90 / 25.5 |

候选通过现有37个引脚、21项活动约束和12个复位落点检查，逻辑/IO锁存器仍为0。但不满足本轮Setup采用条件，故**不晋升、不改正式入口、不重新发布固件**；没有为了保留76 Logic的节省改筛选线、时序约束或布局规则，也未消耗时间复跑已明确失败的候选。

原因证据：原版最差Setup是`u_display/x_d_5_s0 → u_display/base_l1_18_s0`；候选最差变为`u_core/u_b/reset_release_1_s0 → u_core/g_modal.u_bank/u_modal/g_env[1].u_env/env_level_8_s0`。后者经过采样使能、请求预设和包络下一幅度逻辑，报告Logic Level=11、数据布线14.718ns（75.476%），复位释放Q扇出7412。它是进入数据端的Setup链，不是HDMI的Removal检查；没有修改A核心，却因全局重新布局暴露了另一条长链。仅看LUT数或一个模块的RTL写法不能保证整机时序改善。本轮没有擅自扩大到改包络算法或复制系统复位。

验证实际执行：

- 新增`verification/tb/display/tb_ui_map_equivalence.v`，穷举4096×4096×2=33554432组，包括整个屏外坐标范围；全部58位输出同时对照冻结原版和独立算术参考。统计命中钢琴203520、黑键37760、吉他42432、控制区42944；只声明已定义二进制输入的功能等价，不声明X/Z行为或模拟毛刺等价。
- 黑键失去优先级、右边界误含端点两项隔离故障分别在(120,368)、(392,368)被拒绝，ModelSim进程返回非零。最终有效日志为`sim_*_v4`；前期退出脚本的优化隐藏标志/`onfinish stop`/成功误用`$stop`问题已修正，早期运行明确不作通过证据。
- 6项原样测试：`tb_simple_ui_map`、`tb_simple_ui_states`、`tb_practice_display`、`tb_touch_contact_tracker`、`tb_slider_guide_hdmi`、`tb_review_hdmi_reset_recovery`。包括2298个音频样本逐拍隔离、17轮HDMI恢复/2189个四路视频字、28个触点事件；触点测试不代表USB主机已接通。
- 原版与候选各运行一次真实像素/字模/CDC的钢琴及吉他导奏帧，共1228800像素逐字节一致。两个hex文件SHA256分别为`12af50b1e0f9ac04a1b9507a7e5a505339938210d7dd0a1ac0c216d9322f2111`、`3ef3bb1e475d7d24d0e6e7b08da11d6f78819ca2c08a6ed606e9b236cf291951`。
- 195份当前源码/测试严格Verilog-2001编译通过；候选RTL也在穷举及6项集成编译中使用相同严格选项。全部既有TB、正式RTL/ROM/CST/SDC/process及用户配置未改；756份原文件中只有AGENTS/PLAN/本说明更新，其余753份保持原哈希。

本轮机器证据：`verification/evidence/ui_map_parallel/summary.json`。当前正式位流仍是`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 **`2702c933ebde3678f69bd7b61894a2c5f99923bacbb133ab49a5681e5efaba40`**。隔离基线重建资源/余量一致，但其FS哈希不同，不能称与正式FS逐字节相同。未推送、未烧录、未做实物测量；PR1014、完整DAC板外时序、USB触摸及整机模拟延迟缺口均不因本轮测试消失。


## 2026-10-24 实物琴键与蓝牙引脚同步

用户再次确认实物白键C19/D19/C20/F19/E17/F14/D16/D15，明确覆盖刚同步master e578e65的J13-1..8映射；蓝牙RXD→C13、TXD→C14、STATE→C15。五黑键、ADC、原RTL/ROM/队友TB、SDC与Place3/Route1/ClockOrder0保持。更新公共/蓝牙CST、接线合同与独立检查预期及当前接线说明；Sipeed官方31005底板p6/p7/p19与60K核心板p1/p4/p6已重新读取，PDF哈希与合同原来源一致。F14到J13-29经R68，实物连通仍待核对。

Gowin1.9.12.04综合/布局布线及生成位流成功；37实际引脚、21活跃约束、五类时序、输入/位流哈希核验通过；13键/ADC/3路BLE实际Bank、电压和方向与合同一致，7项引脚/电压/报告故障均被拒绝。Logic26338/59904、FF12038/60780、BSRAM90/118、DSP25.5/118、PLL1/8；Setup/Hold/Recovery/Removal/Pulse余量0.077/0.183/0.976/0.144/5.803ns。Setup只有77ps，PR1014仍在，不能表述为时序宽裕或完整板外签核。

新文件`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 `0ce25e1894eafd3e93225ad50ecb91405e9f3d8a1c61b712847052fc2d3953c9`；本机身份`build/hdmi/latest_build.json`，汇总`build/pin_migration_20261024/summary.json`、引脚检查`build/pin_migration_20261024/pin_check.json`。281份RTL/ROM/既有TB/SDC/process等保护文件逐字节不变。已尝试`check_verilog.ps1`，因本机缺少指定ModelSim工具未运行；本轮未重跑RTL功能回归，不借用上游旧结果冒称重测。未提交/推送/烧录，BLE实机、R68/线束、实屏及整机模拟延迟仍待验收。


## 2026-10-24 当前覆盖：32声部与操作界面修复

按用户要求，本地master合入`cleanup/expression-brightness`最新`737f0f4`（合并提交`e8d1ba7`）。正式HDMI采用两组16并行，共32声部；48kHz、原音色系数和固定三效果保留，音频缓存R955，976拍准备窗余21拍。仍以HDMI为唯一发布入口，分支随带旧接线试听包不能用于当前线束。

白键C19/D19/C20/F19/E17/F14/D16/D15、五黑键C18/E19/D20/F15/F16、ADC B20/A21、BLE C13/C14/C15保持。正式导奏关闭；显示AIN2明亮度0～127条和数值；输出条改固定分段对数刻度，音频幅度不变。音量/弯音新增384原码迟滞和弯音中心吸附，保留原音频斜坡及端点/故障恢复，不新增ADC等待。触摸仍没有USB主机/HID驱动，滑条画面不代表支持触摸拖动。

最新`projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 `861aa1557070410a34b7f04caf3c54008c57e9043739a62ec6b680bda29479ba`。Logic39370/FF15859/BSRAM93/118/DSP35.5；Setup/Hold/Recovery/Removal/Pulse=0.562/0.186/0.976/0.144/6.072ns。37引脚、21约束、7项引脚负向检查通过；余量仍有限，PR1014及完整板外时序未闭合。身份见`build/hdmi/latest_build.json`，证据`build/merge32_20261024/summary.json`。

本机16项定向Icarus `-g2001`检查通过，包括实际DPB的24576次读取、ROM替身与原语24580拍等价、新核心1600组PCM/32声部对照和5200个实时周期、256组输入快照对照、正式顶层13实体+19UART填满32槽/第33音抢占、R955及DAC/PA/UART隔离、572组三键及100次重叠换键、17轮HDMI恢复、BLE来源隔离和包络/旋钮/显示检查。长逻辑测试使用单独证明等价的仿真ROM，Gowin仍使用厂商原语；直接原语长回归主动停止，不能说全套原语仿真跑完。ModelSim缺失未做严格检查，PySide6缺失未重跑电脑端测试。已有队友TB、母表ROM、引脚、SDC/process保持；当前工作区还包含未提交的引脚/界面修复，不能只凭HEAD复现位流。

用户确认有线耳机首键正常，蓝牙首音问题暂定位在无线输出链路，未证实具体端点或实现修复。用户确认屏幕只在接电脑时触摸正常。三键误触发在软件测试中未复现，不宣称实物故障已修好；复测仍出现时需抓未按键输入与公共地的波形。未推送、未烧录、未做整机实物验收。


## 2026-10-24 同步master与USB收尾

已快进同步远端 master 至 `df0e894`，在此基础上完成 USB 资源/输出时序修复。32声部采用两组16声部并行，钢琴/吉他、默认合唱/延迟/混响、AIN2明亮度及四来源演奏保留，音频缓存仍为 R955；导奏保持关闭。

正式改动仅 USB 配置描述符共用逐字节读取口、USB D+/D−与输出使能一起寄存，及 Route 1→2（Place3/ClockOrder0不变）。描述符解析每项多9个48MHz周期，正常轮询不改；引脚发送统一延后一拍20.833ns，复位立即高阻。357份既有保护文件逐字节保持，含A音色/ROM、既有TB、引脚和SDC，未放宽约束。

239份严格Verilog-2001、17项主回归、2031组触摸报告、9类USB故障及HDMI恢复故障注入通过。独立候选与正式全量重建通过原39引脚/28条约束检查；正式Logic 44000/59904、FF 20382/60780、BSRAM 93/118、DSP 35.5/118。Setup/Hold/Recovery/Removal/Pulse为 **0.300/0.191/0.642/0.143/5.799ns**，余量仍有限，不能称全面签核。

正式位流仅由构建生成于 `projects/hdmi/impl/pnr/piano_hdmi.fs`，SHA256 `6d9f9621418d95ee4b479ddae7dbab9ece65aa8dc206d169688986c0b0dbf58b`。未打下载包、未烧录、未做实物验收；USB六指/滑奏/方向校准、实体偶发串音、蓝牙首音、PR1014、完整DAC板外时序与实体/触摸整机延迟仍待验证。禁止继续烧录的用户要求仍有效。证据见 `verification/evidence/usb_touch/summary.json`。

原版完整PNR报PR0004（12368条未布通）。72位共享窗口仍有3440条未布通，逐字节描述符读取降到11条；Route2完成布线，但高扇出复位直接到USB输出使能违反原10ns端口上限（最差−7.342ns）。只把数据和使能一起寄存后，原端口约束通过。失败候选保留为隔离证据，不能用于下载。

逐字节解析独立验证1180800字节比较；输出边界验证256组数据/使能、4种复位相位及停钟高阻；封装测试覆盖真实416位信箱及四轮断线/失锁。既有长HDMI测试覆盖13417个满32声部样本、27274个串行字、8904个湿声独存样本，音频R955不变。完整构建是独立重新综合/布局布线，不是把候选fs复制为正式结果。

另外修复DAC证据审计：必须逐项匹配当前构建输入与实现记录，拒绝旧16声部PASS元数据和当前USB清单混用；6项自检通过。DAC数字边沿及故障检查通过，接收器参数/板级偏斜/实测仍缺，signoff=false。USB实现8项、引脚7项故障检查均拒绝预期错误。
