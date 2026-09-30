# 高云 FPGA 电子乐器：A+B+C 集成 demo

面向 Tang Mega 60K NEO Dock **31004**，器件 `GW5AT-LV60PG484AC1/I0`。

已接入队友 GitHub Part_C 的按键消抖、事件编码和声部分配，复用 A 的独立 DDS（相位累加查波表）与 B 的板载音频发送器。

- S2 / AB13：C4；S1 / Y12：E4；可同时按下。
- S4 / AA13：低有效复位。下载后先按一下复位，再低音量试听。
- 四路独立合成声部；普通模式用两个板载键，自动测试模式发送四个音符。
- 50 MHz V22 系统时钟，平均 48 kHz、16 位双声道同样本输出。
- 板载 PT8211-S 使用 16 位 **LSBJ（右对齐）**，不是 Philips I2S 格式。
- 简单起音/释音渐变、固定力度和单一正弦音色；**不是完整比赛作品**。完整 ADSR、两维传感器、实时表情/变调、多音色及整机延迟测量尚未交付。

## 打开、测试和下载

高云 EDA 打开 `fpga_project/fpga_project.gprj`，顶层 `instrument_demo_top`；自动四声部测试顶层为 `instrument_demo_auto_top`（复位后播放一次约 1 秒）。

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
# 负向对照：必须失败，证明原 A+B 检查器能检出数据错误
.\sim\run_tests.ps1 -Suite AB -NegativeControl -ModelSimBin 'C:\Library\modelsim\win64'
```

工程生成 `fpga_project/impl/pnr/instrument_demo.fs`。旧的 `fpga_project.fs` 不是此 demo，不要选错。这里只提供源码/构建流程，不自动操作板卡或刷 Flash。

接线、有效时刻、验证结果和限制见 [demo 说明](docs/abc-demo.md)。

## 目录与责任

| 部分 | 源码入口 | 作用 |
|---|---|---|
| A | `rtl/phase_acc.v`、`wave_lut.v`、`voice_dds.v` | 单声部实时正弦合成 |
| B | `rtl/sample_tick.v`、`i2s_tx.v`、`synth_top.v` | 采样请求、板载 DAC 串行发送、功放控制 |
| C | `rtl/interaction_top.v` 等 | 消抖、音符事件、分配及自动测试事件 |
| 集成 | `rtl/demo_voice_bank.v`、`instrument_demo_top.v` | 四声部、渐变包络、低音量混音和板级连接 |
| 测试 | `sim/`、`tb/`、`model/` | 原 A/B/C 回归与新增集成检查 |

旧 C 说明保留在 [docs/c-interaction.md](docs/c-interaction.md)，原 C 模块/测试仍保留。协作与赛题计划见 [PLAN.md](PLAN.md)。
