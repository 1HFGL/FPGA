# 2026 年 10 月 14 日原始试听固件

[烧录文件：music_classic16.fs](music_classic16.fs)

这是 2026-10-14 20:15:05 构建并保留的原始文件，2026-10-17 按用户要求上传，供队友复测钢琴音色。文件未经重新编译或修改。当天后续反馈“应该是可以了”在项目中记为初步试听可用，完整验收仍以实测为准。

## 身份与校验

- 固件标识：`FW=music-classic16`。
- 目标器件：`GW5AT-LV60PG484AC1/I0 Version B`（60K）。
- 顶层：`music_uart_top`；钢琴 v3／经典摇滚，16 复音，48 kHz。
- 文件大小：20,055,739 字节。
- SHA-256：

```text
55ddab166832b0df000993de6f9ce1d6465862ad961595e29ee67376ac2b1cce
```

GitHub 文件页面可点击 **Download raw file** 下载。可在 PowerShell 中运行 `Get-FileHash -Algorithm SHA256 -LiteralPath '实际下载路径\music_classic16.fs'` 校验。

## 复测步骤

1. 用 Gowin Programmer 的 **SRAM Program** 下载此 `.fs`。
2. 启动仓库内 `host/run_tone_studio.bat`，连接实际 COM 口，波特率 115200。确认握手包含 `FW=music-classic16`、`TONE=PIANO_ROCK`、`MAX_VOICES=16`。
3. 演奏页选择钢琴，总音量先设 **8**，弯音归中（协议值 **512**），用电脑琴键弹奏 C4 及和弦。同一个串口只由一个程序使用。
4. 使用同一音箱和音频接口，与当前 HDMI 固件比较并记录听感。

板载 **KEY0 复位，KEY1=C4，KEY2=E4**；本版通过上位机切换钢琴／摇滚。

这是电脑 UART／板载两键独立试听版，**没有 HDMI 输出、13 个外接琴键、实体旋钮或第三维明亮度控制**。烧录后屏幕不显示属于预期，外接琴键和旋钮不能用于本次复测。

已核对当日实际布局布线报告：所用系统时钟、复位、板载按键、UART 和音频输出的 10 个引脚，与当前 60K 主工程对应引脚一致。本固件不使用当前 J13 外接键／ADC 信号。

当日完整记录见仓库 `docs/listening-acceptance.md` 与 `docs/music-verification.md`。本次仅上传历史固件和本说明，不代为操作下载器；新一轮板上复测结果待反馈。
