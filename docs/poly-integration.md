# A 最新四声部模块的板级接入

后续更新：同日代码审查修复C的四项问题并减少资源，完整回归增至26项，两套位流已再次重建；当前数据和交付边界以 [审查报告](code-review-20261006.md) 为准。以下是上午接入阶段的历史记录，保留原结果，不把其“未推送”状态当作后续交付状态。

日期：2026-10-06。基于 A 分支 `c8286e2`，在本地 `codex/adsr-integration` 接入；用户原有未提交修改保留。本次没有提交、推送、烧录或实物测量。

## 改了什么

- `instrument_adsr_top` 普通／自动版改用 A 的 `voice_bank_adsr`，由其内部 `sample_mixer4` 完成四路扩位、缩放与饱和混音。
- C 的 `voice_trigger` 接到 A 的 `voice_retrigger`，A 的 `release_done` 回送 C；不把 A/C 两个同名 `voice_active` 输出接在同一根线上。
- 高云工程加入两个新源码；旧 `adsr_voice_bank` 及旧渐变 demo 保留，原测试条件不放宽。
- C→A 的抢占／重触发／尾音回收测试改测新 bank；普通与自动版均逐字核对串行输出、左右声道、首帧静音、欠载、R4缓存、复位及实际非零样本。
- 负向测试使用独立波形文件，保存脚本覆盖新旧共22项回归。

## 接口与预期效果

仍用31004板卡、V22名义50MHz、48kHz目标采样率、16位有符号音频和原8个物理端口；CST／SDC未改。所有内部逻辑在同一个系统时钟域，采样请求是时钟使能。B的 `audio_ready` 统一释放复位，A同步复位须经历时钟上升沿；外部KEY0仍可异步关闭功放。

请求R0采纳音符、增益和包络；R1为单声部ADSR样本，R2为增益样本，R3混音有效，B在R4缓存并于下一帧发送。尾音最后零样本到达混音输出后才允许C回收；这不是DAC已经播完的反馈，也不是整机延迟实测。

保持 `MIX_SHIFT=5`（总和除以32），四声部理论输出范围 `[-4096,4095]`。新A模块的数字增益127表示单位增益，1～126按值/128；旧 bank 的127表示127/128，不能混用参考模型。普通按键与自动版仍固定100，故该边界区别不改变当前演奏的增益。

KEY0复位、KEY1=C4、KEY2=E4，可两键同时演奏。仍是单一正弦音色，包络默认起音2ms、衰减500ms、保持约10%幅度、释放120ms。自动版触发MIDI36～39四个相邻低音，约1秒后松键，尾音结束后静音；复位重新触发一轮。不是歌曲、13键钢琴或电子鼓，没有ADC旋钮、第二音色和外部实时变调。

## 实际验证

- ModelSim SE-64 10.6e：`-Suite All` 22项通过，正常编译和测试日志无Error／Warning；原旧bank测试仍保留。
- Python 3.12.14：DDS、单声部ADSR、旧ABC、A新四声部及旧ADSR bank五个参考检查通过。新bank默认38379样本／边界2721样本，旧bank61097样本；新bank边界测试覆盖正负饱和。
- 串行负向对照在10530ns报告 `intentional ADSR serial mutation`，脚本非零拒绝；正式RTL不含该故障。
- Gowin V1.9.12.04、GW5AT-LV60PG484AC1/I0、Device Version B：普通和自动版均完成综合、布局布线及 `.fs` 生成，50MHz下Setup／Hold违例0/0，8/8端口均Constraint=Y；主时钟、异步输入例外及输出布线预算均Actived。

| 工具报告 | 普通版 | 自动版 |
|---|---:|---:|
| 最差Setup／Hold裕量 | +6.271／+0.162ns | +5.534／+0.123ns |
| 工具Fmax | 72.836MHz | 78.788MHz |
| LUT／ALU／寄存器 | 2251／607／1147 | 2983／604／985 |
| pROM／DSP | 4／8 | 4／8 |

自动版最差Setup路径终点为PA_EN，使用本地输出预算；内部最差Setup为+7.308ns。以上报告不是板卡实测频率，也不是完整外部接口或硬件可靠性签核。PR1014非专用输入时钟路由告警仍保留；NL0002是各模式未用模块被优化。DAC实际为PT8211-S的LSBJ格式，外部DAC时序和比赛I2S口径仍待验证，不勾选R1—R7。

## 复现与文件选择

在仓库根目录运行（其他电脑替换为实际工具路径）：

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
# 使用真实Python 3运行 model/check_dds.py、check_adsr.py、check_abc_demo.py、
# check_poly_adsr.py、check_adsr_mix.py；Windows Store别名不能代替Python。
Push-Location .\fpga_project
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_auto_demo.tcl
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_demo.tcl
Pop-Location
.\sim\save_adsr_evidence.ps1 -Destination 'results/自己的新证据目录'
```

保存前需另运行 `-Suite ADSRDemo -NegativeControl`，必须非零拒绝。两个高云构建共用工程配置，不并行运行，最后普通版保留顶层 `instrument_adsr_top`、输出名 `instrument_adsr`。

新普通文件为 `fpga_project/impl/pnr/instrument_adsr.fs`，新自动文件为 `instrument_adsr_auto.fs`，本轮已于10月6日重新生成。证据、报告及源码／位流哈希见 [本轮记录](../results/poly-integration-20261006/README.md)。原10月2日两份位流和改动前文件已备份到该目录的 `rollback/`（本机忽略，不上传）；旧渐变版 `instrument_demo.fs` 未改。

下一步由组员按现有31004接线和低音量耳机方案试听普通版，覆盖单键、双键、长按、提前松键、释放中重按和复位。新版本尚未上板，下载成功也不等于这些行为验证通过。
