# Delay、Chorus 与混响：自动轻效果版

2026-10-17，按用户要求在现有混响之后的开发阶段补齐 Delay 和 Chorus。两个正式工程默认开启三种效果，钢琴与经典摇滚电吉他共用同一条效果链，不需要额外按键、触摸屏或上位机命令。KEY0复位，KEY1中→高→低→中，KEY2切乐器；13实体键、UART、音量和弯音旋钮保持原操作，仍为16复音、48kHz。

## 烧录文件与对照

本轮包：`build/audition/delay_chorus_j13_20261017/`。

| 用途 | 新版：三效果默认开启 | 对照：仅上轮混响 |
|---|---|---|
| HDMI屏＋实体键＋双旋钮 | `hdmi_delay_chorus_j13.fs` | `hdmi_reverb_only_reference.fs` |
| 无屏入口 | `piano_delay_chorus_j13.fs` | `piano_reverb_only_reference.fs` |

下载器选 `.fs`，`.gprj` 是源工程。对照文件来自上轮已经核验的混响包，没有重新构建或覆盖历史发布包；各文件来源、大小、SHA256见同目录 `manifest.json` 与 `summary.json`。当前源工程重新编译默认得到三效果版。

固定参数是这一轮可试听的起点，不是已经确认的最佳听感。三效果用于修饰乐器的声音，不算增加演奏声部或可控表情维度。当前仍是单声道合成，两个DAC声道输出相同；不宣称立体声扩展。USB触摸物理接收仍未实现，明亮度滑条与这些固定效果分开。

## 如何试听

先把音箱与板上音量调低。每次换固件按KEY0复位，在同一音箱、同一音区和相同旋钮位置先比较一次。新链路的直达声幅度约为原效果器输入的53.3%，上轮仅混响版为75%，所以新版起音约比上轮低3dB；第二轮可小幅调整音箱响度匹配后再比较，不要用“更响”判断效果好坏。

1. **Delay（回声）**：中音区短按单音再松手，间隔至少2～3秒。除原有尾响，应能听到约160ms后的轻回声及更弱的后续重复；不是无限重复，也不应突然变响。钢琴原包络可能遮住回声，可换吉他短音更容易比较。
2. **Chorus（合唱）**：保持单音或C/E/G和弦约2秒，与仅混响版比较。预期有轻微厚度和缓慢变化，拨弦/击弦仍清楚；不应有剧烈晃音、周期性咔嗒或像换了一个音符。它有意产生轻微音高变化，不改变按键对应音名。
3. **和弦与快速演奏**：弹三音、四音和弦，再快速交替弹15～30秒。各音应同时开始，不能卡音、爆音或因效果叠加变成明显糊团。两种乐器、低中高三个音区都检查；上位机原有16声部检查仍可使用。
4. **切换与旋钮**：按住旧音再切音区或乐器，已有音按原规则保持，新音采用新设置。调整音量与弯音应连续；由于效果位于音量之后，之前写入的回声会按原能量继续衰减，转小音量不是立即清空尾声。
5. **静音与复位**：松开所有键后等原乐器尾音结束，再等待约3秒，应没有反复冒出的旧音、数字残音或自激。尾声中按KEY0应清除历史，复位后未按键不能自行发声。复位强行截断波形的瞬态与自然松键分开判断。

合格条件是以上操作稳定、两个乐器仍可辨、尾音自然消失。若吉他和弦糊或钢琴晃音明显，请记录乐器/音区/和弦和对照结果，再降低相应效果比例。数字仿真和构建不能替代你们的实际音箱试听；模拟音箱自身底噪也不能凭数字零输出判定已解决。

## 实现和资源约束

链路为：A模态合成/总音量 → 可选明亮度 → Chorus → Delay → 原Room Reverb → B缓存 → DAC。两个新增模块只处理实时合成的混音结果，保留原A模型、ROM、原混响实现、引脚、时序约束及工程过程配置。

- **Chorus**：1024×16位循环RAM，两路独立三角LFO约0.60Hz和0.83Hz；抽头分别约10.67～13.33ms、16～18.67ms。分数延时采用相邻样本线性插值，再平均两路；81.25%直达＋18.75%合唱。一次接收R0、R11有效、下游R12消费，新增12拍。其原理可参考[Julius O. Smith 的 Chorus 说明](https://www.dsprelated.com/freebooks/pasp/Chorus_Effect.html)和[延迟线插值](https://www.dsprelated.com/freebooks/pasp/Delay_Line_Signal_Interpolation.html)，RTL独立编写。
- **Delay**：7680×18位循环RAM，48kHz下160ms，内部带2位小数。每轮写入为5/8新输入＋3/8旧回声；87.5%直达＋12.5%延时输出。采用归一化反馈以限制持续信号增益，第一声回声比直达明显轻，之后逐次衰减。R0接收、R4有效、下游R5消费，新增5拍。
- **数值与复位**：符号扩展、向零截断及饱和，避免负数右移残留永久的微小直流。RAM不整片清零，以填充年龄屏蔽复位前内容；非零单元计数跨越静音间隔维持尾声状态。尾声和最后输出全部归零后，沿用B的真实DAC帧排空策略再静音。
- **时间预算**：新两级共增加17个50MHz时钟，即0.34μs计算时间。三效果正式HDMI缓存R953、无屏R950，原最小976拍准备窗口内分别余23、26拍。160ms是回声间隔，直达声仍按当前DAC帧输出，不是新增160ms琴键延迟；实体键到模拟声音的整机延迟仍待实测。
- **存储预算**：最终实现新增10块BSRAM（Chorus 1块、Delay 9块；Delay映射为9条8192×2位SDPB）；HDMI共114/118块，仅余4块，无屏100/118块。详细资源与时序以本轮 `summary.json` 为准，不能仅凭LUT利用率判断还能容纳更长延时或更多声部。

默认满幅正脉冲的独立Delay测试中，最后可见非零输出在1.28秒，内部状态在1.92秒完全归零；三效果级联的脉冲静音测试同样最终归零。它们是特定数字输入的结果，不是所有乐器包络或真实声学混响时间的保证。

## 验证与复现

`model/check_delay_chorus.py` 使用样本队列建立独立参考，不复制RTL状态机。851000组输入覆盖正负满幅脉冲、持续信号、小信号、随机、脏RAM复位及多个LFO转折/回绕。新 `tb_delay_chorus` 同时验证两个模块各自0/默认/100%湿声共6种配置，并检查忙时拒绝、有效拍数、流水线各位置复位和尾音。

`tb_effects_hdmi` 在两个正式顶层实际48kHz节拍下同时检查16个发声声部、两乐器/音区/旋钮、R953/R950、串行DAC字及HDMI断连/丢锁/停钟隔离；每级输出另经Python逐样本比较。ADC值在规范化边界注入；后半段主动把合成源置零以孤立效果器，不是完整物理松键包络测试。

`tb_effects_pa` 加速输入130000样本，确认声部分配器已空时仍保持回声和混响，跨越零间隙，最后排空DAC并静音。此项不作为真实48kHz整机延迟证据。原测试文件未改；`--dry`关闭三种效果，`--reverb-only`只保留混响，`--legacy`显式验证原兼容合同，不能把这些当作新版三效果集成证据。

```powershell
# 从仓库根目录执行；先把工具变量设为本机实际路径。
& $Python -X utf8 model/check_delay_chorus.py
& $Python -X utf8 model/check_room_reverb.py
& verification/scripts/check_verilog.ps1 -ModelSimBin $ModelSimBin
& $Python -X utf8 verification/scripts/run_final_tests.py tb_delay_chorus tb_room_reverb tb_effects_pa tb_effects_hdmi tb_final_hdmi_isolation tb_hdmi_octaves --bin $ModelSimBin --gowin-simlib $GowinSimlib
& $Python -X utf8 model/check_delay_chorus.py --capture build/regression/effects/hdmi_audio.csv
& $Python -X utf8 verification/scripts/run_final_tests.py tb_reverb_hdmi --reverb-only --bin $ModelSimBin --gowin-simlib $GowinSimlib
& $Python -X utf8 verification/scripts/run_final_tests.py tb_touch_hdmi_audio --dry --bin $ModelSimBin --gowin-simlib $GowinSimlib
& $Python -X utf8 verification/scripts/run_final_tests.py tb_hdmi_audio_isolation --legacy --bin $ModelSimBin --gowin-simlib $GowinSimlib
& projects/hdmi/build.ps1 -Gowin $Gowin -Python $Python
& projects/piano/build.ps1 -Gowin $Gowin -Python $Python -EvidenceDirectory build/effects-noscreen
& $Python -X utf8 verification/scripts/package_delay_chorus.py
```

要重建仅混响版，正式顶层设 `ENABLE_CHORUS=0, ENABLE_DELAY=0, ENABLE_REVERB=1`；完全干声设三者均0，再完整构建。公共兼容核心三项默认均0，正式顶层默认均1。当前包不提供运行时效果开关，避免占用已有控制。

验证摘要位于 `verification/evidence/effects/summary.json`。仍保留原PR1014时钟布线提示、完整DAC外部时序/电气与整机模拟延迟待验收项；只能称当前约束下通过实现检查。未替用户烧录、未完成实物听感验收、未推送本轮改动。
