# C 部分代码审查报告

日期：2026-09-24

## 1. 已有 Gowin 结果

Gowin 在 20:05 已完成一次 32 声部版本的 Synthesis 和 Place & Route：

```text
Logic         1196 / 59904   2%
Register      1514 / 60780   3%
I/O             8 / 297      3%
最差 Setup Slack  +9.440 ns
```

结论：

- 32 声部控制逻辑资源占用很低；
- 50 MHz 下时序有明显裕量；
- 当前瓶颈不在 C 部分的声部管理。

Gowin 仍有一个警告：

```text
PR1014: Generic routing resource will be used to clock signal 'sys_clk_d'
```

当前时序为正，不阻塞功能，但正式版本可以考虑显式全局时钟缓冲。

注意：这次综合时：

```text
pressure_valid = 0
expr_valid = 0
```

因此 pressure 和 expression 相关逻辑在 `board_top` 中可能被优化掉。接入 A 部分后必须重新评估资源和时序。

## 2. 本次审查已经修复的问题

### 2.1 复位后的假按下

`input_sync_debounce.v` 原来在复位时把同步器和稳定状态都置 0。对于低有效按键，这会让内部 raw_level 在复位后错误地变成 1，去抖计时结束后产生一次假的 press_pulse。

已修复：

- 复位时同步器初始化为空闲电平；
- 测试平台增加复位后空闲检查。

### 2.2 event/expr 握手竞争

`voice_allocator.v` 原来在空闲周期同时给出 `event_ready` 和 `expr_ready`，当 note 事件和表情事件同时到达时，两个发送方可能都认为自己被接受。

已修复：

- `event_ready` 和 `expr_ready` 改为状态组合输出；
- note 事件优先；
- 有 note 事件时 `expr_ready` 立刻为 0。

### 2.3 FIFO 满时读写同地址

`event_encoder.v` 原来在 FIFO 满时允许同一周期同时读写同一地址。异步读 LUTRAM 的读写冲突行为不应依赖。

已修复：

- FIFO 满时先不写，下一周期先读；
- 代价只有一个时钟周期，不影响音频延迟。

### 2.4 压力滤波器多延迟一拍

`pressure_if.v` 原来用旧 filter_acc 更新 pressure_filtered，导致多一个采样周期延迟。

已修复：

- 先计算 filter_next；
- pressure_filtered、velocity 和 pressure_active 都在同一拍使用新滤波值。

### 2.5 32 声部 LED 状态错误

原来使用 voice_count 的低两位控制 LED，32 声部时显示为 0。

已修复：

```text
LEDs[2] = voice_count != 0
LEDs[3] = max_voice_count >= 4
```

## 3. 当前最重要的剩余问题

### P0：缺少 32 声部硬件测试源

当前 `board_top` 只有两个物理按键，所以按按钮最多只能启动两个 voice。32 声部控制器虽然存在，但 FPGA 顶层没有自动产生 32 个 note_on 的测试模式。

建议增加：

```text
voice_test_pattern
  -> 1/4/8/16/32 个 note_on
  -> 不同频率或不同 note
  -> note_off 和 release_done 测试
```

### P0：表达式事件按 note 匹配不够严谨

当前 `expr_note` 用来寻找 voice。如果同一个 note 同时存在两个 voice，表达式可能更新到错误的声部。

建议增加：

```text
source_id 或 voice_id
```

让 note_on 和后续 pressure/pitch/vibrato 事件使用同一个 source_id。

### P0：每路输入的力度还没有独立采集

当前 `event_encoder` 只有全局 `input_velocity`。多个按键同时演奏时，它们会共享同一个力度值。

建议接口改为：

```text
key_press[KEY_COUNT-1:0]
key_velocity[KEY_COUNT-1:0][6:0]
```

或使用事件 FIFO 写入每路独立力度。

### P1：复位没有同步器

`sys_rst_n` 直接作为异步复位使用。建议增加 reset synchronizer，采用异步复位、同步释放。

### P1：A 的 release_done 仍然是假信号

`board_top` 当前使用：

```verilog
release_done = 32'hFFFFFFFF
```

正式联调要接 A 部分的真实 release_done，并测试随机 Release 延迟。

### P1：验证强度还不够

建议增加：

- 32 个 note_on 同时到达；
- FIFO 接近满和满状态；
- event_valid 与 expr_valid 同时到达；
- note_off 和 release_done 同周期；
- 随机 1000 次 press/release；
- Python golden model 自动比对。

## 4. 推荐修改顺序

```text
1. voice_test_pattern
2. source_id / voice_id 表达通道
3. 每路独立 velocity
4. A 部分 synth_stub + release_done 随机测试
5. reset synchronizer
6. 随机测试和 Python golden model
7. 重新做 Gowin 综合、资源、时序和 GAO 验证
```
## 5. 后续已完成升级

- 已增加 source_id 事件通道；
- 已增加每路独立 velocity 接口；
- 已增加 voice_test_pattern；
- 已增加 board_test_top 32 声部自动测试顶层；
- 已增加 reset_sync；
- 已增加 tb_voice_test_pattern；
- 六套 ModelSim 测试全部通过；
- Gowin 工程文件已加入新 RTL。
