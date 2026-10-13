# 板键ADSR与旧渐变演示工程

2026-10-13迁移说明：本目录保留四种活动构建模式。四个Tcl均从脚本路径定位工程，先恢复根目录`process_config.json`，再设置对应顶层和输出名；必须串行执行。ROM搜索根为仓库根，GPRJ引用`../../../rtl/`分组目录和已核实板级约束。

下文是2026-10-02至08的历史试听／验证记录，保留原数字和哈希供追溯；这些哈希不代表迁移后的新构建。历史输出在`../../legacy/`，本轮构建证据请看新的build目录和B审查报告。不要仅按旧文件名或本页历史哈希下载当前源码生成的位流。

# 高云 EDA A+B+C demo 工程

2026-10-08钢琴感候选：请打开 [UART钢琴感独立工程](../../piano/README.md)，下载目标为 `../../piano/impl/pnr/instrument_uart_piano.fs`；原正弦UART和两键工程保留。固定音色，没有运行时调参；仿真与当前约束实现检查通过，未实物验证，PR1014及DAC外部时序仍待解决。

2026-10-08：电脑控制请打开 [UART基础演奏独立工程](../../uart_basic/README.md)，不是下面的原两键工程。新UART位流 `../../uart_basic/impl/pnr/instrument_uart.fs` 已生成并完成本地验证，未上板；固定正弦／ADSR、共享四声部，不支持界面调参。原工程及普通／自动位流保留，以下记录属于原两键版本。

保持整个仓库的相对目录结构，在 EDA 的 File → Open Project 打开本目录 `fpga_project.gprj`。

2026-10-07补充：三种ADSR算术候选均已退出正式工程，当前源码仍为10月6日审查版；普通／自动位流已用原RTL重新生成，资源／时序数字不变。27项回归通过。试验快照已归档于docs/reports/legacy目录，勿加入GPRJ；若归档新证据，需同时运行 `ADSRMath` 和 `ADSRDemo` 两个负向检查。见 [试验记录](../../../docs/adsr-optimization-20261007.md)。

2026-10-06审查后：普通／自动顶层已接入A最新 `voice_bank_adsr` 和 `sample_mixer4`，C分配器四项问题已修复并压缩排名资源，原bank／旧demo保留。26项仿真、五个参考程序和负向检查通过；两版下载文件已重新生成。50MHz下最差Setup/Hold普通+6.619/+0.125ns、自动+5.669/+0.123ns，违例0/0，8/8端口约束。普通版LUT/寄存器为2119/965。PR1014及完整外部DAC时序仍待验证，新版未下载。当前配置保留普通顶层。见 [审查报告](../../../docs/code-review-20261006.md) 与 [接入说明](../../../docs/poly-integration.md)。

- 器件：GW5AT-60B / GW5AT-LV60PG484AC1/I0 / Device Version B。
- 新普通ADSR顶层：`instrument_adsr_top`，KEY1／KEY2弹奏C4／E4，KEY0复位；输出名 `instrument_adsr`。
- 新自动ADSR顶层：`instrument_adsr_auto_top`，约1秒后进入120ms释放；输出名 `instrument_adsr_auto`。
- 旧渐变顶层 `instrument_demo_top`／`instrument_demo_auto_top` 保留作回退，不与新ADSR下载文件混用。
- 板卡：用户确认 NEO Dock 31004；V22 名义 50MHz，按键 BANK9 为 1.5V，音频为 3.3V。
- 约束：`../../../boards/tang_mega_60k_31004/demo.cst` 与 `demo.sdc`。
- ROM Include Path 为 `../../..`，保留 `rtl/rom/sine_1024.mem`。

已检测并实际运行本机 Gowin 1.9.12.04；从仓库根目录执行：

```powershell
Push-Location .\projects\examples\adsr
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_demo.tcl
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_auto_demo.tcl
Pop-Location
```

其他电脑把可执行文件路径换成自己的安装位置。脚本只构建，不连接板卡、不刷Flash。两个脚本共享工程配置，不要并行运行；最后运行哪版，就核对GUI顶层与输出名是哪版。交付时配置为新普通ADSR版。本机GUI若缓存旧设置，请重新打开工程并检查。

新输出为 `impl/pnr/instrument_adsr.fs`、`instrument_adsr_auto.fs`，当前PNR目录只保留这两版的实现产物。旧单音/渐变版输出已归档至 `../../legacy/pnr-20261007/`。回退时可使用其中的旧渐变位流，或用原 `build_demo.tcl`／`build_auto_demo.tcl` 重新生成 `impl/pnr/instrument_demo.fs`／`instrument_demo_auto.fs`。大体积下载文件、工作库和工具缓存不提交。**归档中的旧 `fpga_project.fs` 自动分配了引脚，不要下载它。**

历史C按键/LED工程已由根目录移到 `../../legacy/c_interaction/tang_mega_60k_interaction.gprj`，其约束和原编译输出一起保留。10条源码引用修正为 `../../../rtl/`；原GUI配置及输出内容不变。该历史工程只用于追溯/交互调试，试听使用本目录的 `fpga_project.gprj`。整理未重新运行高云实现，位流身份仍按原构建记录核对。

## 当前上板试听说明

2026-10-07注释补充不改变发声逻辑。19个改动RTL文件去除注释后的词法记号与 `d909b17` 一致；GPRJ、活动配置、CST、SDC及两份位流的SHA256与同日优化试验归档一致。本轮不重新综合/布局布线，不覆盖位流，也没有操作板卡。源码文件哈希因注释变化而不同，旧实现报告仍归属于改注释前的构建。

注释后已重跑ModelSim SE-64 10.6e完整27项回归并全部通过；本次日志及源码哈希见 [验证归档](../../../docs/reports/legacy/comments-20261007/)。未重跑Python参考或负向注错检查，不把此前结果冒充这轮新运行。

先选普通版 `impl/pnr/instrument_adsr.fs`（本机生成时间2026-10-07 15:44:07），不要选 `_auto` 或旧 `fpga_project.fs`。普通版SHA256为 `D4AA25CC26B58CBC0B8B6E908DB1A8E6477A176451BF4667B67C18E965230A71`。核对仍为NEO Dock 31004、GW5AT-60B及现有接线，再按已使用的 `SRAM Program` 方式做临时试听；本步骤不要求刷Flash或新增音箱。先把耳机放在耳外确认无异常杂音，再试听；数字低增益不是听力安全保证。

以下是源码和仿真支持的**预期**，不是这份位流已经上板观察到的结果：

| 普通版操作 | 应有现象 |
|---|---|
| 下载/KEY0复位后，KEY1和KEY2均松开 | 静音，不会自动演奏；本顶层没有LED反馈功能 |
| 按住KEY1 | C4，名义约261.63Hz，较纯的正弦电子音，不是逼真的钢琴声 |
| 按住KEY2 | E4，名义约329.63Hz，比KEY1高 |
| 同时按住KEY1和KEY2 | 两个音叠加；左右耳机收到相同混音，不是左耳一个音右耳另一个 |
| 按住超过约0.5秒 | 2ms渐强至峰值，再500ms衰减到约10%峰值幅度并持续；后段明显较轻是设计行为 |
| 松开一个键，另一个仍按住 | 松开的音从当前幅度约120ms淡出，另一个继续响 |
| 两键都松开 | 尾音结束后静音；120ms从消抖后的松键被采样起算，不是实测手指到静音时间 |
| 释放过程中重新按键 | 可再次发声；分配器可能另用空闲声部，重按不保证从零相位开始 |
| 发声时按KEY0 | 复位关闭输出；测试时先松开演奏键，再释放KEY0，应恢复静音待机 |

目前固定增益100、混音总和除32，没有音量调节按键；保持段很轻不等于死机。建议逐项测试“KEY1单音、KEY2单音、双键、各自松开、长按、重按、复位”，记录异常，不先通过加大数字增益掩盖问题。内部有四个独立声部，但普通版只有两个物理演奏键；这不是四路不同音高的实物验收。

`instrument_adsr_auto.fs` 则在启动后自动触发MIDI 36/37/38/39（C2/C#2/D2/D#2）四个相邻低音，约1秒后松开，再约120ms淡出。不是歌曲或悦耳和弦，也不会循环。再次按KEY0可重播；自动模式始终选择测试事件，KEY1/KEY2不能像普通版演奏。自动版SHA256为 `7130AD23B3FB05618E9B8422F1A3E1B66B853833C201DEAAA5C6DB025FC4DA3C`。

13键、旋钮、第二音色、钢琴/鼓音色与外部实时变调均未接入。已有PR1014时钟路由告警、DAC外部时序和整机延迟仍待验证；这次试听不是整机可靠性或比赛验收。

## 历史构建备注

2026-10-02新ADSR普通／自动版已实际综合、布局布线和生成下载文件，50MHz下Setup／Hold违例为0，8个端口已约束。时序裕量很小，PR1014及完整外部DAC时序仍待验证，尚未下载新版本。见 [ADSR集成说明](../../../docs/adsr-integration.md)。

原单音顶层和通用 25MHz 的 `audio_clk.sdc` 仅保留为仿真/历史参考，不再是本工程的活动顶层或时钟约束。完整接口、验证和上板步骤见 [demo 说明](../../../docs/abc-demo.md)。
