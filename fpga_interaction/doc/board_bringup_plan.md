# Tang Mega 60K 首板调试清单

## 目标

先按顺序验证：

```text
开发板供电
  -> USB JTAG/UART
  -> Gowin Programmer 识别器件
  -> 下载示例
  -> LED
  -> 两个用户按键
  -> C 部分去抖和事件编码
  -> 32 声部测试模式
  -> 接入 A/B 和 I2S DAC
```

不要一开始就接音频功放、DAC 或复杂外设。先保证下载链路和基本 IO 正常。

## 第 0 步：检查板卡和供电

1. 只在开发板断电时连接或拔掉排线。
2. 确认底板电源开关处于关闭状态。
3. 按 Sipeed 手册连接 12V DC 或 USB 调试口。
4. 需要开机时，长按 `PWR` 约 2 秒。
5. 观察电源指示灯。

验收：

```text
开发板稳定上电
没有异常发烫
没有反复重启
```

## 第 1 步：验证 Gowin Programmer

1. 用 USB 线连接开发板的 USB JTAG & UART。
2. 打开：

```text
D:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer.exe
```

3. 扫描 JTAG。
4. 确认识别到 GW5AT 器件。
5. 如果无法识别，检查 USB 驱动、线缆、供电和 JTAG 扫描模式。

验收：

```text
Programmer 能看到器件
不是只看到空白器件列表
```

## 第 2 步：先测普通按键板级版本

工程：

```text
D:\AI tools\Codex&GPT\files\fpga_interaction\tang_mega_60k_interaction.gprj
```

顶层：

```text
board_top
```

操作：

1. 打开工程。
2. 确认顶层为 `board_top`。
3. 执行 `Project -> Clean...`。
4. 运行 `Synthesize`。
5. 运行 `Place & Route`。
6. 生成 `.fs`。
7. 在 Programmer 中选择 SRAM 下载。

验收：

- 下载成功，没有 `PR2017/PR2028`。
- 不按按键时，状态 LED 应处于空闲状态。
- 按 `Key_in[0]` 后，LED0 点亮，LED2 点亮。
- 按 `Key_in[1]` 后，LED1 点亮，LED2 点亮。
- 松开后，对应声部释放，LED 熄灭。

如果 LED 全部反相，把 `board_top.v` 中：

```verilog
parameter integer LED_ACTIVE_LOW = 0
```

改成：

```verilog
parameter integer LED_ACTIVE_LOW = 1
```

然后重新综合和下载。

## 第 3 步：使用 GAO 看内部信号

首次抓取建议加入：

```text
Key_in
key_level
key_press
key_release
event_valid
event_type
event_note
voice_active
voice_gate
voice_count
max_voice_count
steal_pulse
```

验收：

- 一次按键抖动只出现一个 `key_press`。
- 一次松开只出现一个 `key_release`。
- 一次按键只生成一个正确的 `note_on`。
- `voice_count` 随按键增加和减少。
- 松开后声部能释放。

## 第 4 步：测试 32 声部控制模式

把顶层切换为：

```text
board_test_top
```

重新：

```text
Clean
Synthesize
Place & Route
Program Device
```

测试模式会在一轮内产生：

```text
1 -> 4 -> 8 -> 16 -> 32
```

当前版本 `board_test_top` 配置为：

```text
TEST_VOICES = 32
```

验收：

- 测试开始后，`voice_count` 能达到 32。
- `max_voice_count` 能达到 32。
- 测试保持期间 LED2 点亮。
- `max_voice_count >= 4` 后 LED3 点亮。
- 测试结束后，note_off 和 release_done 能让声部清零。

## 第 5 步：验证 UART

需要先确认 FPGA B 部分已经提供命令解析器。

目标协议：

```text
STATUS?
TEST 32
CLEAR
NOTE_ON 60 100 0
NOTE_OFF 60 0
TIMBRE 2
ADSR 10 30 90 40
VOLUME 100
FX REVERB 64
```

验收：

- PC 发送 `STATUS?`。
- FPGA 返回包含 `VOICE_COUNT` 和 `MAX_VOICE_COUNT` 的状态行。
- PC 发送 `TEST 4` 后，FPGA 真正启动 4 声部测试。

## 第 6 步：接入 A 和 B

在 A/B 的正式 RTL 接入 Gowin 工程后，按以下顺序联调：

1. 只接一个声部。
2. 检查 `voice_gate` 到波表输出的通路。
3. 检查 ADSR 和 `release_done`。
4. 增加到 4 声部。
5. 增加到 32 声部。
6. 检查混音是否溢出。
7. 接入 `sample_tick`。
8. 接入 I2S。

## 第 7 步：接入 I2S DAC

1. 确认 DAC 的 I2S 格式、主从模式和采样率。
2. 确认 MCLK、BCLK、LRCK、SDATA 的电平和方向。
3. 先输出单音。
4. 再输出 4 音。
5. 再输出 32 音。
6. 用示波器或逻辑分析仪检查 I2S。
7. 用音频接口和 PC 软件检查 FFT 谱峰。

## 第 8 步：延迟测量

测试流程：

```text
触发按键
  -> 记录触发时刻
  -> 采集 DAC 输出
  -> 找到第一个有效音频样本
  -> 计算时间差
```

需要记录：

```text
最小延迟
最大延迟
平均延迟
抖动
```

基础验收：

```text
总延迟 <= 10 ms
```

冲国赛目标：

```text
总延迟 <= 5 ms
且抖动确定
```

## 现在最先执行的三件事

```text
1. 给开发板供电并用 Programmer 扫描到 GW5AT
2. 下载 board_top
3. 按两个用户按键，用 LED 和 GAO 检查按键和声部分配
```

只有这三步全部通过后，再进入 A/B 音频联调。