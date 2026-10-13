# 两套乐器预设：31004 板载按键烧录版

此版本把 2026-10-08 的拨弦／弦乐核心连接到板载按键和 PT8211-S 音频输出。用户已于 2026-10-09 确认仍使用 Tang Mega 60K + NEO Dock 31004 以及板载耳机口。

## 打开哪个工程、下载哪个文件

在高云 EDA 的 **File → Open Project** 打开以下仓库相对路径（前面加上你实际的仓库目录）：

```text
projects/examples/instruments_board/instruments_board.gprj
```

顶层应为 `instrument_presets_top`，器件为 `GW5AT-60B / GW5AT-LV60PG484AC1/I0`。这次工程与昨天的 `instruments_check` 分开；后者是独立时序外壳，不能代替板级工程。

已生成的下载文件位于：

```text
projects/examples/instruments_board/impl/pnr/instruments_board.fs
```

无需重新手动添加 RTL、波表或约束。其他电脑需要保留完整仓库相对目录，不能只拷贝 `.gprj`。高云进程配置使用本工程的 `process_config.json`；构建脚本会将其复制到工具的 `impl` 配置位置，并设置顶层及 ROM include path。

## 下载和试听

1. 给板卡正常供电，用数据线连接原来可用的 DEBUG 下载口。首次试听先把耳机放在旁边。
2. 从高云打开 **Programmer**，选择已经能识别板卡的下载线，点击 **Scan Device/扫描器件**。
3. 扫描结果应为相应的 `GW5AT-60B`。双击器件行，在 **Operation** 选择 **SRAM Program**，在 **Programming File/FS File** 选择上面的 `instruments_board.fs`。
4. 确认器件行已勾选，点击 **Program/Download**。输出日志明确显示成功后再进行试听。不要选择旧 demo、独立时序外壳或 Flash 擦除操作。
5. 按一下 **KEY0**，进入默认拨弦预设。按住 **KEY1** 发出固定 C4（中央C）；声音快速起音后自然变小，长时间按住会衰减到静音。
6. 松开 KEY1，按一下 **KEY2**，再按住 KEY1。这时是弦乐持续预设：起音较缓，按住保持声音，松开后约171ms释放。
7. 再按一次 KEY2 即切回拨弦。每次 KEY0 复位都回到拨弦。

KEY2 是消抖后的单次切换，长按不会来回切换。按住 KEY1 或仍有尾音时按 KEY2，当前音保持旧乐器，下一次 KEY1 起音才采用新乐器；如果两个按键消抖后的按下事件恰好落在同一拍，则采用切换后的新乐器。实际试听建议先按 KEY2，再按 KEY1，以免两个触点的抖动先后影响选择。

SRAM 下载是本轮临时试听方式，断电后需要重新下载；没有改动 Flash 内容。下载器的基本流程依据 [高云 Programmer 用户指南 SUG502](https://cdn.gowinsemi.com.cn/SUG502E.pdf) 的设备扫描、配置与下载章节。下载成功并不自动等于音频接线或音质验收通过。

本版保留 `/32` 的低增益与固定力度100。昨天的电脑WAV试听做了播放响度对齐，板上没有那一段软件播放增益，因此实际音量不一定相同。先确认能正常听到声音再判断音色。

## 实现与范围

新顶层位于 `rtl/top/instrument_presets_top.v`，复用原同步消抖、B 的 `synth_top/sample_tick/i2s_tx` 以及新 `voice_bank_instruments`。两键在同一50MHz时钟下处理，音频目标48kHz。KEY1只驱动第0声部，MIDI60、力度100；其余声部保持关闭。这是板载单键对比试听，不是13键或四键演奏版，也不替换团队的完整声部分配器。

按键消抖器的电平先于事件脉冲更新，因此顶层从事件统一注册 `play_gate/play_trigger`，避免同一次按键碰到采样边界时重复起音。新音采用当次事件的乐器快照。

采样请求R0，经亮度、包络、力度、混音后R4输出，B在R5缓存，下一帧输出左右相同样本。核心静音后功放使能再延长3个采样边界，让B的待发/活动帧排空；KEY0仍会立即关闭功放并复位串行输出。

板载PT8211-S使用16位 **LSBJ（右对齐）**，沿用团队模块名 `i2s_tx`，不声称是标准Philips I2S一位延迟格式。所有内部逻辑使用 `sys_clk`；BCK只是输出信号，不作为内部时钟。

| 端口 | 管脚 | IO 电平 |
|---|---|---|
| sys_clk | V22 | LVCMOS33，名义50MHz |
| sys_rst_n / KEY0 | AA13 | LVCMOS15，上拉 |
| Key_in[0] / KEY1 | AB13 | LVCMOS15，上拉 |
| Key_in[1] / KEY2 | Y12 | LVCMOS15，上拉 |
| HP_BCK | Y17 | LVCMOS33 |
| HP_WS | AB17 | LVCMOS33 |
| HP_DIN | AA16 | LVCMOS33 |
| PA_EN | AB16 | LVCMOS33，1关闭功放 |

物理约束来源于仓库此前已核对的31004 Rev1.4原理图与厂家CST；本轮只更新KEY2用途说明，没有猜测或新增外部引脚。J27/J28桥接扬声器端不属于本次耳机试听连接。

## 重新构建和验证

在仓库根目录运行：

```powershell
.\verification\scripts\run_tests.ps1 -Suite PresetsBoard -ModelSimBin 'D:\modelsim1\win64'
& 'C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' projects/examples/instruments_board/run.tcl
python model/check_presets_board.py
```

如果自己修改了源码，必须重新综合和布局布线后再下载生成的新 `.fs`。GUI中双击 **Synthesize**、成功后双击 **Place & Route**，完成后检查报告和输出文件时间。

测试只缩短消抖/包络时长以覆盖按键与串行协议，保留真实50MHz/48kHz节拍；昨日的核心测试负责默认包络时长与独立数学核对。板级测试核对正负样本、R4/R5、两声道逐位解码、唯一启动欠载、选择锁存、复位和功放尾音。负向控制故意翻转观察的串行位，必须报错退出，不是另一份可下载设计。

本轮实际构建、约束覆盖、资源、位流哈希及回归日志见 [板级验证记录](reports/instruments_board_20261009/README.md)。时序报告中的输出0～20ns约束只是本地寄存器到引脚预算，尚不替代DAC外部建立/保持余量的实物测量；继承的V22通用时钟输入路由提示也保留。助手生成了可下载文件，没有操作用户板卡，实际声音仍由用户本次下载试听确认。
