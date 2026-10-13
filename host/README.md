# FPGA 实时乐器控制台

2026-10-08 “声场”音色设计台已重绘为独立的深色合成器工作台：双击 `run_tone_studio.bat`。
支持谐波/包络编辑、配置保存载入、单周期波表、模拟设备与经过握手确认的串口连接。
使用说明见 [STUDIO_README.md](STUDIO_README.md)，待 FPGA 接入的协议见 [STUDIO_PROTOCOL.md](STUDIO_PROTOCOL.md)。
下文是保留的旧控制台说明；启动入口已改用项目根目录的 `.venv-studio`，不再依赖旧电脑的 `D:\python`。旧串口命令未证明已接入当前 FPGA；旧声学延迟测试测的是电脑音频路径，不能作为乐器整机验收。

这是一个面向高云 FPGA 电子乐器项目的 PC 辅助软件，负责串口控制、声部监控、测试模式、频谱分析、延迟测量和波表生成。

## 启动

双击：

```text
run_fpga_tool.bat
```

或从项目根目录执行：

```powershell
& '.venv-studio/Scripts/python.exe' host/main.py
```

旧控制台还需要本目录 `requirements.txt` 中的依赖；当前 `.venv-studio` 只确认具备音色设计台所需的 PySide6 和 pyserial，尚缺旧控制台的 numpy、scipy、pyqtgraph、sounddevice 等。本轮目录迁移没有安装依赖，也没有验证旧控制台可启动；优先使用 `run_tone_studio.bat`。旧入口失败时会显示错误，不会自行安装软件。

## 功能

### 1. 连接与测试

- 选择串口和波特率；
- 连接 FPGA；
- 显示 `VOICE_COUNT`、`MAX_VOICE_COUNT`、`STEAL_COUNT` 和 `SAMPLE_RATE`；
- 发送 `TEST 1/4/8/16/32`；
- 发送 `CLEAR`；
- 发送 `STATUS?`；
- 发送任意文本命令。

### 2. 乐器控制

- 设置音色编号；
- 设置音量和 ADSR；
- 设置效果器和效果量；
- 使用虚拟钢琴；
- 使用电脑键盘演奏；
- 可选 MIDI 输入；
- 保存和加载参数。

电脑键盘映射：

```text
Z S X D C V G B H N J M
```

对应一个八度内的 12 个半音。

### 3. 频谱与延迟

- 选择音频输入设备；
- 实时显示 FFT；
- 统计有效谱峰数量；
- 执行简单的声学延迟测量。

### 4. 波表生成

- 正弦波；
- 三角波；
- 锯齿波；
- 方波；
- 加法合成；
- 导出 `.hex`、`.mif` 和 `.csv`。

## FPGA UART 协议

软件发送 UTF-8 文本命令，每条命令以换行结束。

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

FPGA 返回状态可例如：

```text
VOICE_COUNT=32 MAX_VOICE_COUNT=32 STEAL_COUNT=1 SAMPLE_RATE=48000
```

## MIDI 说明

当前 Python 环境未安装 `python-rtmidi`，因此 MIDI 硬件输入会显示为不可用。虚拟钢琴和电脑键盘仍然可以正常使用。以后安装与 Python 版本匹配的 `python-rtmidi` 后，软件会自动启用 MIDI 输入。

## 依赖

```text
PySide6
pyqtgraph
pyserial
sounddevice
numpy
scipy
mido
```
