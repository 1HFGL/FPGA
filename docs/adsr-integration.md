# 四声部 ADSR 集成与上板候选

历史记录说明：本文对应2026-10-02旧bank接入。2026-10-06已替换板级合成核心为A最新 `voice_bank_adsr`／`sample_mixer4` 并重跑22项回归及两版高云实现，输出路径相同但位流已更新；最新行为、位宽规则和验证结果以 [本次接入说明](poly-integration.md)为准。

日期：2026-10-02；基础版本为团队 `master` 的 `e7dd27a`，接入 A 的 `adsr_env`、`sample_gain`、`voice_adsr` v2。远程查询未发现更新的 C 提交。新增内容位于本地 `codex/adsr-integration`，本次不自动推送、合并或下载板卡。

## 当前能做什么

- KEY0复位，KEY1按住弹C4，KEY2按住弹E4，支持两键和弦。
- 四个独立正弦合成声部，各有相位和完整ADSR；自动版触发四个音符，约1秒后松键，再释放120ms。
- 默认48kHz目标下，A/D/S/R为96点／24000点／6554（Q1.16）／5760点，即2ms／500ms／约10%峰值幅度／120ms。S是电平，不是时长。
- 起音或衰减中松键，从当时幅度进入完整释放；重按／重触发从当前幅度重新起音。
- 仍是单一正弦音色、固定力度100/127，不是已经完成的13键钢琴；没有ADC旋钮、第二音色或外部实时变调。新的下载文件尚未实物试听。

## 模块与接口

`instrument_adsr_top` 连接 C 的事件／分配、`adsr_voice_bank` 和 B 的输出。旧 `instrument_demo_top` 与 `demo_voice_bank` 保留原渐变功能，原检查条件不放宽。

- C新增 `voice_trigger[VOICES-1:0]`：成功应用每个note-on后的一拍脉冲，同音重复与声部抢占也输出；与更新后的gate／音符对应。不是事件被接收时就触发，也不是用gate高电平代替。
- A的 `retrigger` 会暂存采样间隔中的脉冲；gate为0时松键优先。新音符的gate状态须保持到采样，不能把完整按下松开压成一个无法采到的脉冲。
- 所有逻辑共享50MHz系统时钟；B异步断言、两拍同步释放复位，A高有效同步复位使用 `~audio_ready`。外部KEY0可立即关闭功放；A寄存器在下一个系统上升沿清零。
- 请求R0更新DDS／包络并快照力度；R1包络乘法；R2力度乘法；R3混音有效；B在R4接收，下一帧发送。不是把新样本直接放进当前帧。
- `release_done` 在混音拍确认gate为0、包络空闲且该声部缩放样本为0后生效；C据此回收尾音结束的槽。
- 每声部计算 `floor(floor(raw * env / 65536) * velocity / 128)`；乘法分别保留34位和24位，负数向负无穷舍入。四路显式扩到18位相加，再算术右移5位。
- /32保留低音量余量，输出理论范围[-4064,4063]；力度127对应127/128，不宣称单位增益。此阶段有数值界限保证，不依赖截断实现饱和。

物理引脚、1.5V板载按键、3.3V音频口、LSBJ格式及测量安全说明沿用 [旧demo说明](abc-demo.md)。未增加物理端口，CST／SDC未改。PT8211-S是右对齐LSBJ，不宣称Philips I2S或比赛接口已经认可。

## 构建、仿真与文件选择

高云EDA打开 `fpga_project/fpga_project.gprj`，新普通顶层为 `instrument_adsr_top`、输出名为 `instrument_adsr`。若本机GUI缓存旧配置，请手工核对；自动顶层为 `instrument_adsr_auto_top`。

从仓库根目录执行，本机路径换成各自安装位置：

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
python model/check_dds.py
python model/check_adsr.py
python model/check_abc_demo.py
python model/check_adsr_mix.py
Push-Location .\fpga_project
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_demo.tcl
# 可选自动版，勿与普通版同时运行，两个脚本共享工程配置。
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_auto_demo.tcl
Pop-Location
```

`python`如是Windows Store别名，须换成真实Python 3路径。`-Suite ADSR`只跑三项新增A模块测试；`-Suite A`跑六项；`-Suite ADSRDemo`跑17项；`-Suite All`跑新旧共20项。已补齐ADSR独立套件的DDS依赖，并传入单声部轨迹导出参数。

负向检查故意翻转串行比较值，下面命令**必须非零失败**，不用于正常通过：

```powershell
.\sim\run_tests.ps1 -Suite ADSRDemo -NegativeControl -ModelSimBin 'C:\Library\modelsim\win64'
```

| 用途 | 下载文件 |
|---|---|
| 新普通ADSR版 | `fpga_project/impl/pnr/instrument_adsr.fs` |
| 新自动四声部ADSR版 | `fpga_project/impl/pnr/instrument_adsr_auto.fs` |
| 旧渐变回退版 | `fpga_project/impl/pnr/instrument_demo.fs`，用 `build_demo.tcl`重建 |

先核对31004、器件、8个引脚和下载文件身份，再由组员用匹配GW5AT-60B的SRAM Program下载。KEY0复位后应静音；低音量分别按KEY1／KEY2、同时按、长按、提前松键、释放中重按。先验证普通版，再试自动版。不刷Flash，不让助手自动操作硬件。

## 实际验证与限制

- ModelSim SE-64 10.6e：原17项＋新增三项，共20项通过；正常日志均无Error／Warning。
- 新四声部参考核对61,097个样本、两个复位、每声部全部五个包络状态；覆盖不同阶段释放、零／最大力度、同音重触发、混音正负值和最终静音。
- 原DDS参考、单声部ADSR参考及旧ABC混音参考继续通过。单声部为162,085个时钟、47,734个样本、14个复位周期。
- 联合仿真保持真实50MHz／48kHz目标，只缩短包络参数用于加速：检查R4接收、首帧零、LSBJ逐字匹配、非启动阶段无欠载、按键抖动、释放与中途复位。不能据此报告实物毫秒延迟。
- C→A测试检查四声部、第五键抢占、同源同音重触发、被抢占音符松键及释放回收；负向串行检查以非零状态拒绝。
- Gowin1.9.12.04、GW5AT-LV60PG484AC1/I0、版本B：普通／自动版综合、布局布线和下载文件生成完成；50MHz下Setup／Hold违例均0，8/8端口已约束。
- 普通版最差Setup／Hold裕量+0.025／+0.123ns；自动版+0.067／+0.143ns。裕量很小，后续修改必须重跑时序，不视为硬件可靠性签核。
- PR1014非专用输入时钟路由警告保留；NL0002对应各模式未用模块优化。外部DAC约束仍只是本地输出布线预算，不是完整外部接口时序验收。

报告、源码／约束／下载文件身份与日志见 [本轮证据](../results/adsr-integration-20261002/README.md)。未执行下载或实物测量，不勾选比赛R1—R7。下一步先由用户试听新普通版，再推进第二音色和13键／旋钮，不扩展32复音。
