# SYNTH/1 上位机接口合同

当前正式无屏/HDMI主工程只实现NOTES/STATUS，握手为 `SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=16 SAMPLE_RATE=48000 FW=uart-dual-v1 TONE=PIANO_GUITAR`。无CONFIG，APPLY返回UNSUPPORTED；KEY2切换钢琴／吉他，当前模态钢琴释放约85.33ms，吉他约42.67ms再加箱体收尾。使用见[上位机说明](README.md)与[主工程](../README.md)。

2026-10-15模式集成后，正式声部容量已从VOICES透传，默认兼容入口仍报告4而不是被强制改成16。PC新音使用板上当前模式，旧音/尾音保留起音预设；两音色共享16席位，不是各16。当前没有远程MODE命令，STATUS也没有当前模式、旋钮、延音、八度、显示或触摸字段；上位机只提示“钢琴／吉他（KEY2切换）”，不假装知道当前选中哪种。默认电脑模拟钢琴报告16声部，仅用于PC交互验证。

以下CONFIG字段是PC与模拟设备已实现的未来协议，不是当前FPGA能力。固定固件白名单明确接受FIXED_SINE、FIXED_PIANO和PIANO_GUITAR；未知TONE或带CONFIG能力的设备不能据此绕过APPLY确认。旧正弦板级工程已从当前仓库移除、可从Git恢复。实际串口与听音需上板验证。

## 传输与握手

- 默认 UART 115200、8 数据位、无校验、1 停止位；电脑和 FPGA 必须一致。
- ASCII 文本，以 LF（0A）结束；接收端可容忍 CRLF。每行最多 512 字节（不含 LF）。超长/非法行丢弃到下一 LF；不允许执行半条命令。
- 上位机打开串口发送 `HELLO`；设备应在 1800 ms 内回复：

```text
SYNTH/1 CAPS=CONFIG,NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=version-id
```

`MAX_VOICES` 为真实支持的独立声部数，1～32；`SAMPLE_RATE` 为设备名义采样率，8000～192000 Hz，不代替采样率测量。`FW` 无空格。`CONFIG` 必须完整支持本版本配置字段才可宣告；只支持状态读取则仅宣告 `STATUS`，新界面将禁用配置与演奏。

## 原子配置命令

```text
APPLY sequence h1,h2,...,h16 attack_ms decay_ms sustain release_ms volume mode vibrato_cents vibrato_tenths_hz CRC
```

- `sequence`：1～2147483647，连接之间继续递增；每次只有一个配置请求在途。
- `h1`～`h16`：0～255，对应基频的 1～16 倍频相对幅度，全部零为静音。
- `attack_ms` / `decay_ms` / `release_ms`：0～10000 毫秒；0 是即时阶段，禁止计数器下溢。建议由固件在接收配置时按采样率换算，规则：`floor((ms * Fs + 500) / 1000)` 个采样点（非负，半点向上）。
- `sustain` / `volume`：0～255，线性幅度比例 `value / 255`，不是主观响度；16 位幅度的精确缩放、舍入及饱和需在 FPGA 接入前固定并验证。
- `mode`：0 持续（按住走 ADSR，松键立即进入释放）；1 击发（起音到峰值后用 decay_ms 衰减至零，忽略持续电平，不依赖持续按住）；2 混合（起音和衰减为最小击发段，期间松键暂存释放请求，段末再进入释放；仍按住则保持持续电平，随后松键释放）。不是当前 RTL 已有功能。
- `vibrato_cents`：0～100 音分，0 关闭；`vibrato_tenths_hz`：1～120，单位 0.1 Hz。参考频率变化：`f(t)=f_note * 2^(depth * sin(2*pi*rate*t)/1200)`；最终固件需定义定点近似和验证，不依赖 PC 发音。
- `CRC`：4 位十六进制 CRC-16/CCITT-FALSE，poly=1021、init=FFFF、不反射、xorout=0000。覆盖从 `APPLY` 首字符到速度参数最后一位的 ASCII 字节，不包含 CRC 前分隔空格、CRC 和 LF；已知向量 `123456789`→29B1。

字段范围、数量、CRC 全部通过后暂存；在音频采样边界一致切换，禁止中途逐字段更新。已有声部在采样边界采用新配置；改变包络段长/模式应重初始化当前包络的算法状态，并在 RTL 合同中定义行为及回归。上位机应用前会发送 `PANIC`，但固件仍须支持健壮处理非静音时的配置。

实际切换后回复 `APPLIED sequence`；拒绝则回复 `ERROR sequence CODE`，例如 `BAD_CRC`、`RANGE` 或 `UNSUPPORTED`，保留旧配置。上位机只认对应请求的成功回执；超时状态未知，不自动重发，不宣称已应用。

## 音符与状态

```text
NOTE_ON note velocity source
NOTE_OFF note source
PANIC
STATUS?
STATUS VOICE_COUNT=0 MAX_VOICE_COUNT=4 STEAL_COUNT=0 SAMPLE_RATE=48000
```

- `note` 0～127 为 MIDI 编号；`velocity` 0～127，当前界面固定 100；`source` 当前界面固定 0。
- `NOTE_OFF` 按来源和音符匹配；重触发、尾音释放、抢占必须保留每声部独立状态，不能用界面模拟数据代替 FPGA 验证。
- `PANIC` 仅停止由上位机来源发起的声部，不能无条件吞掉实体按键的状态；由固件在采样边界执行。
- `VOICE_COUNT` 为固件实际占用的声部（包括释放尾音）；`MAX_VOICE_COUNT` 为本次启动峰值；`STEAL_COUNT` 为累计抢占。采样率由设备报告，仍需实物验证。
- 支持 `STATUS` 时，上位机每秒查询一次；发音事件优先于诊断流量。建议固件对上位机来源设置通信失联回收机制，避免拔线后卡音；具体时限需在接入时验证。本次模拟设备断开即清除模拟音符，不模拟真实包络或发声。

电脑端附加行为：配置确认期间禁止新起音，但松键不依赖配置是否确认；超时尝试PANIC。松键或PANIC提交失败会保留并重试。连续3秒未收到有效STATUS时会话失效，停止状态查询/新起音，重新HELLO后不重放旧音符。此行为不新增固件命令，也不把串口写入当作设备已执行的证明。

## FPGA 接入前需要明确

当前UART引脚见主工程CST（RX=V14、TX=U15），基础命令接入已存在。若扩展CONFIG，仍需验证整行解析、原子参数提交和硬件定点规则。现有 ADSR 编译参数不能直接当作运行时寄存器；谐波合成、颤音和上述发声模式需分别开发与验证。软件生成的波表是单周期参考，不是预录 PCM。

## A独立试听固件：PRESET／CONTROL

以下仅适用于 `projects/music/uart_music.gprj` 报告的 `TONE=PIANO_ROCK`，不代表正式 `PIANO_GUITAR` 入口支持这些命令。上位机同时检查NOTES、STATUS、PRESET能力，不以设备名称猜测协议。

```text
PRESET 0
PRESET 1
CONTROL 127 512
STATUS ... PRESET=1 VOLUME=127 BEND=512
```

PRESET 0为摇滚吉他、1为钢琴，状态中的PRESET是确认依据。CONTROL须明确报告CONTROL能力，音量0～127、弯音0～1024（512居中）；整对提交，40ms合并连续拖动，完整VOLUME/BEND状态对才更新确认值。确认超时不伪装成功。失联／重新握手清空在途预设与控制状态，不重放旧演奏。此处不增加CONFIG能力，谐波／包络草稿仍不能应用到这些固定预设。
