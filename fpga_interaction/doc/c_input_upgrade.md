# C 部分输入层升级说明

本次升级对应系统框图：

```text
13 个琴键 -> 同步与消抖 -> 按下/松开事件 -> 声部分配

音色切换按键 -> 音色编号

两个旋钮 -> ADC 采集与参数映射 -> A/B

A 的尾音结束反馈 -> C 的 release_done
```

## 1. 13 个琴键

`interaction_top` 参数默认改为：

```verilog
KEY_COUNT = 13
NOTE_BASE = 60
```

音符映射：

```text
key[0]  -> note 60
key[1]  -> note 61
...
key[12] -> note 72
```

每个琴键都有独立同步、消抖、按下脉冲和松开脉冲。

## 2. 音色切换按键

新增：

```text
timbre_key_n
timbre_id[3:0]
timbre_press
```

每次按下音色键，`timbre_id` 自动循环：

```text
0 -> 1 -> 2 -> ... -> 7 -> 0
```

音色编号随 note_on 事件进入 A 部分。

## 3. 两个 ADC 旋钮

新增模块：

```text
rtl/adc_knob_if.v
```

输入：

```text
knob_raw_flat[23:0]
knob_valid
```

输出：

```text
knob_value_flat[13:0]
knob_param_valid
param_ready
param_fault
```

映射关系：

```text
knob0[6:0]  -> master_volume   （A 部分主音量，旋钮 0）
knob1[6:0]  -> tone_brightness （A 部分音色亮度，旋钮 1）
```

两个通道都经过数字滤波，12 位 ADC 数据映射为 7 位控制值。

输出采用逐采样 slew 平滑（`SLEW_STEP`，默认 1），避免旋钮快速旋转时产生“拉链噪声”。

## 4. 就绪和故障状态

`adc_knob_if` 会向 B 部分提供：

```text
param_ready
param_fault
```

如果 ADC 连续一段时间没有有效采样，则置位 `param_fault`。

## 5. 尾音结束反馈

保留并强化：

```text
release_done[31:0]
```

A 的当前声部尾音结束后，将对应的 `release_done[i]` 置 1，C 的 `voice_allocator` 随即释放该声部。

## 6. 板级兼容

物理开发板当前仍只有两个可接入的用户按键，因此 `board_top` 内部：

```text
Key_in[1:0] -> key_n[1:0]
其余 11 个琴键 -> 固定为未按下
```

这样既能做现有板级调试，又保持 13 键接口不变。

## 7. 新增测试

```text
tb_adc_knob_if.sv
tb_keyboard_extended.sv
```

验证内容：

- 13 键中的 note60 和 note72 映射正确；
- 音色键能切换音色编号；
- 两个 ADC 旋钮能正确映射，且输出经过 slew 平滑（不会瞬间跳变）；
- ADC 就绪和故障状态正确；
- 声部仍能分配给正确音符。

测试结果：

```text
PASS: tb_adc_knob_if knob0=127 knob1=64
PASS: tb_keyboard_extended notes=60,72 timbre=1 knob0=127 knob1=64
PASS: tb_interaction_top_32key key/LED path and voice allocation
PASS: tb_voice_allocator_32 voices=31 max=32 steal=1
```

## 8. 与 A/B 的接口

新增：

```text
timbre_id[3:0]
knob_value_flat[13:0]
knob_param_valid
param_ready
param_fault
```

A 部分读取音色编号、master_volume（旋钮 0）、tone_brightness（旋钮 1）；B 部分读取 param_ready / param_fault。
