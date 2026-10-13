# A+B 单音联合仿真说明

本文件只说明一个正弦声部的数字链路：A 的 `voice_dds` 接 B 的 `synth_top`，通过板载 PT8211-S 所需的 16 位 LSBJ 串行格式输出左右相同的样本。它是联合仿真/验板准备，不是已经能用按键演奏的完整乐器，也不证明赛题 R1—R7 已达标。

## 连接与前提

- 入口：`rtl/top/single_tone_demo_top.v`；输入 `clk_in`、低有效 `rst_n`、`audio_enable` 和 32 位 `phase_inc`；输出 BCLK、LRCLK、DIN、低有效功放控制 `pa_en` 及欠载指示。
- 全部 RTL 使用同一个 `clk_in`。B 的 `sample_request` 是单周期采样使能，不是派生时钟；它直连 A 的 `sample_tick`。A 的 `sample[15:0]` 和 `sample_valid` 直连 B 的样本输入。
- `phase_inc` 必须由与 `clk_in` 同步的逻辑提供；不能把异步多位外部输入直接接进此端口。改变它后，A 在下一次采样请求使用新步长，并保持相位连续。
- `audio_enable=0` 只关闭功放，数字串行输出仍在工作。当前 DDS 接近满幅，没有音量/包络，不应直接把本例当作安全的实物播放方案。
- 本通用单音代码默认 25 MHz、48 kHz、16 位样本，仿真使用缩小参数。25 MHz 不是 31004 V22 的时钟；2026-09-30 板级 ABC 顶层明确用 50 MHz，见 [ABC demo](abc-demo.md)。实际 ROM 初始化与 DAC 输出仍待上板验证。

## 复位合同

| 事件 | B 输出链路 | A 单音 DDS |
| --- | --- | --- |
| `rst_n` 拉低 | B 的寄存器异步复位，`audio_ready=0`，功放关闭 | `rst=~audio_ready=1`；在下一次 `clk_in` 上升沿清零相位、样本和 valid |
| `rst_n` 释放后的第 1 个上升沿 | `audio_ready` 仍为 0，不发采样请求 | 继续保持同步复位 |
| 释放后的第 2 个上升沿 | `audio_ready` 变为 1 | 此沿仍看到旧的 `audio_ready=0`，继续复位 |
| 后续上升沿 | B 开始产生帧节拍 | A 已退出复位，等待第一笔请求 |

外部 `rst_n` 拉低须至少跨过一个 `clk_in` 上升沿，才能确保 A 的同步状态被清零。测试平台在串行字发送中间拉低复位，检查 B 的功放/串行安全状态，以及 A 在时钟沿后的相位和 valid 复位；这不是对真实异步复位可靠性的板级证明。

## 一笔样本的有效时刻

| 时刻 | A（`voice_dds`） | B（`i2s_tx`） |
| --- | --- | --- |
| 帧起点上升沿 R0 之前 | `sample_request=1`，A 尚未输出本次结果 | 仍只有上一笔缓存 |
| R0 上升沿 | A 接受请求，用**旧相位**读正弦 ROM，同时推进相位；沿后 `sample_valid=1`、`sample_data` 为本次样本 | B 读取旧缓存并启动当前帧；上电首帧输出零，`sample_underrun=1` |
| R0 后的下一个主时钟上升沿 | A 沿后撤销 `sample_valid`，样本数据保持 | B 在该沿读到旧 `sample_valid=1` 和样本，写入 pending 缓冲 |
| 下一帧起点 R1 | A 接受下一次请求 | B 从 pending 取出 R0 的样本，右、左两个 16 位时隙各发一次；只要样本按时到达，欠载为 0 |

这是一帧的数字缓冲延迟，名义 48 kHz 下一个采样帧约 20.8 μs；不等于含传感器、包络、DAC、功放和声学输出的整机延迟实测值。板载 PT8211-S 是 LSBJ 格式，与赛题所写“I2S”的严格协议口径仍需确认。

## 可重复验证

在本机 ModelSim SE-64 10.6e 下运行：

```powershell
.\verification\scripts\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
```

2026-09-28 实测结果：6 个测试平台全部通过；编译及各项仿真均为 0 errors、0 warnings。其中 `verification/tb/integration/tb_single_tone_ab.v` 用独立四象限参考值检查 A 的相位/样本，重组 DAC 串行位并检查左右声道、首帧欠载、下一帧送样、实时变调、复位释放两拍和字中复位。日志、输入文件 SHA-256 清单和波形在 `build/regression/logs/`、`build/regression/waves/`（已忽略，不随仓库提交）；清单名为 `All_sha256.txt`。

检查测试是否能抓住错误：

```powershell
.\verification\scripts\run_tests.ps1 -Suite AB -NegativeControl -ModelSimBin 'C:\Library\modelsim\win64'
```

这条命令**应失败**：测试平台故意翻转帧 1 右声道的一个观察位。实测脚本退出码为 1，日志报告 `expected=0000 actual=8000`。此版 ModelSim 自身遇 `$fatal` 可能仍退出 0，因此脚本同时检查日志 Fatal/Error 和 PASS 标记。负向编译使用独立工作库，不修改交付 RTL。

单音顶层还已在 [高云工程](../projects/README.md) 中通过 GowinSynthesis，识别 1 个 pROM。尚未执行：布局布线、完整约束/时序检查、ROM 板上初始化检查、真实 DAC 发声或端到端延迟测量。
