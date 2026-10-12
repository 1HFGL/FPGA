# C 部分 32 声部升级说明

## 1. 升级目标

将原来的 4 声部控制升级为面向竞赛的 32 声部控制层，并增加：

- 每声部音符、力度和音色；
- 每声部弯音、触后、颤音深度和颤音速率；
- note_on/note_off 握手；
- ADSR release_done 握手；
- 当前活跃声部数；
- 历史最大活跃声部数；
- note_on/note_off/抢占次数；
- 64 项事件 FIFO。

## 2. 修改的 RTL 文件

```text
rtl/voice_allocator.v
rtl/interaction_top.v
rtl/board_top.v
rtl/event_encoder.v
```

### `voice_allocator.v`

- 参数 `VOICES=32`；
- 使用状态机扫描 32 个声部，避免一次性做巨大的组合逻辑搜索；
- 支持同音重触发；
- 支持空闲声部优先；
- 支持释放中的声部优先；
- 支持最老按住声部抢占；
- 支持每声部表情数据；
- 输出性能计数器。

### `event_encoder.v`

- 默认 FIFO 深度从 8 增加到 64；
- 默认指针宽度增加到 6；
- 保留 note_on/note_off 握手。

### `interaction_top.v`

- 默认 `VOICES=32`；
- 增加 `expr_valid` 和每声部表情输入；
- 增加 32 声部状态和表情输出总线；
- 增加性能计数器输出。

### `board_top.v`

- 使用 32 声部配置；
- `release_done` 暂时全 1，独立上板测试时立即释放；
- 板载 LED 显示：

```text
LEDs[0] = Key_in[0] 状态
LEDs[1] = Key_in[1] 状态
LEDs[2] = 当前有活跃声部
LEDs[3] = 历史最大声部数达到 4
```

## 3. ModelSim 操作

工作目录：

```text
D:\AI tools\Codex&GPT\files\fpga_interaction\sim
```

推荐直接运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\run_modelsim.ps1
```

或者在 ModelSim 中执行：

```tcl
do compile_all.do
vsim work.tb_voice_allocator
run -all
```

关键测试结果应为：

```text
PASS: tb_voice_allocator_32 voices=31 max=32 steal=1
PASS: tb_interaction_top_32key key/LED path and voice allocation
```

## 4. Gowin 操作

1. 关闭当前打开的 RTL 文件或重新打开工程；
2. 执行 `Project -> Clean`；
3. 运行 `Synthesize`；
4. 运行 `Place & Route`；
5. 运行 `Timing Analysis Report`；
6. 生成新的 `.fs`。

如果只剩原来的 `PR1014` 时钟布线提示，可以先继续上板测试。出现新的 `PR2017/PR2028` 时，优先检查 `.cst` 是否仍包含 `LEDs[4:7]`。

## 5. 与 A 部分的接口

声部状态：

```text
voice_active[31:0]
voice_gate[31:0]
voice_note_flat[223:0]            // 32 x 7 bit
voice_velocity_flat[223:0]        // 32 x 7 bit
voice_timbre_flat[127:0]          // 32 x 4 bit
voice_pitch_bend_flat[511:0]      // 32 x 16 bit
voice_aftertouch_flat[255:0]      // 32 x 8 bit
voice_vibrato_depth_flat[255:0]   // 32 x 8 bit
voice_vibrato_rate_flat[255:0]    // 32 x 8 bit
```

第 `i` 个声部切片：

```verilog
voice_note_flat[7*i +: 7]
voice_velocity_flat[7*i +: 7]
voice_timbre_flat[4*i +: 4]
voice_pitch_bend_flat[16*i +: 16]
voice_aftertouch_flat[8*i +: 8]
voice_vibrato_depth_flat[8*i +: 8]
voice_vibrato_rate_flat[8*i +: 8]
```

A 部分 Release 完成后，把：

```text
release_done[i]
```

置 1，通知 C 部分释放第 i 个声部。

## 6. 性能计数器

```text
voice_count        当前活跃声部数量
max_voice_count    运行以来的最大活跃声部数量
note_on_count      已接受的 note_on 数量
note_off_count     已匹配的 note_off 数量
steal_count        发生声部抢占的次数
steal_pulse        发生抢占时的单周期脉冲
```

这些信号可以先接入 GAO，后续接入 UART 或测试模式。

## 7. 下一步建议

- 把 A 部分的 `release_done` 真实接入，替换 `board_top` 中的 `32'hFFFFFFFF`；
- 增加 `synth_stub`，随机模拟 Release 延迟；
- 用 Python 生成 32 声部随机事件序列并比对；
- 增加比赛测试模式的 1/4/8/16/32 声部输出；
- 把 `voice_count`、`max_voice_count` 和 `steal_count` 加入 GAO 抓取列表。
## 8. source_id 与每路独立力度

事件编码器现在为每个事件增加 `source_id`：

```text
source_id 0 -> Key_in[0]
source_id 1 -> Key_in[1]
```

每个按键也有独立力度输入：

```text
key_velocity_flat[KEY_COUNT*7-1:0]
```

声部分配器会保存 `source_id`，表情更新优先按 `source_id` 匹配，而不是只按 note 匹配。这样可以避免同一个 note 有两个声部时表情更新到错误声部。

## 9. 32 声部自动测试模式

新增：

```text
rtl/voice_test_pattern.v
rtl/board_test_top.v
```

`voice_test_pattern` 会自动产生：

```text
1/4/8/16/32 个 note_on
等待一段时间
产生对应的 note_off
```

测试模式使用：

```text
board_test_top
```

它已经固定为：

```text
TEST_MODE   = 1
TEST_VOICES = 32
```

普通演奏使用：

```text
board_top
```

普通模式下 `TEST_MODE = 0`。

## 10. 复位同步

新增：

```text
rtl/reset_sync.v
```

它采用异步复位、同步释放，避免外部复位按钮释放时出现亚稳态或恢复/移除时间问题。

`board_top` 现在把外部 `sys_rst_n` 先接入 `reset_sync`，再送给后续逻辑。

## 11. 更新后的 ModelSim 测试

当前完整测试包括：

```text
tb_input_sync_debounce
tb_pressure_if
tb_event_encoder
tb_voice_allocator
tb_interaction_top
tb_voice_test_pattern
```

预期结果：

```text
PASS: tb_input_sync_debounce press=1 release=1
PASS: tb_pressure_if filtered=4000 velocity=121
PASS: tb_event_encoder on=2 off=2
PASS: tb_voice_allocator_32 voices=31 max=32 steal=1
PASS: tb_interaction_top_32key key/LED path and voice allocation
PASS: tb_voice_test_pattern on=4 off=4
```

## 12. Gowin 重新操作

1. 重新打开工程：

```text
tang_mega_60k_interaction.gprj
```

2. 执行：

```text
Project -> Clean...
```

3. 先做普通键盘版本验证，确认顶层为：

```text
board_top
```

4. 运行：

```text
Synthesize
Place & Route
Timing Analysis Report
```

5. 需要测试 32 声部时，把顶层切换为：

```text
board_test_top
```

6. 重新运行：

```text
Synthesize
Place & Route
```

7. 生成新的 `.fs` 并下载。

测试模式下，LED 逻辑为：

```text
LEDs[2] = 当前有活跃声部
LEDs[3] = 历史最大声部数达到 4
```

当 32 声部测试运行时，两个 LED 都应该点亮。

## 13. 与 A 部分的接口更新

新增：

```text
voice_source_id_flat[159:0]       // 32 x 5 bit
```

第 i 个声部的 source id：

```verilog
voice_source_id_flat[5*i +: 5]
```

A 部分可以继续使用：

```text
voice_active
voice_gate
voice_note_flat
voice_velocity_flat
voice_timbre_flat
voice_pitch_bend_flat
voice_aftertouch_flat
voice_vibrato_depth_flat
voice_vibrato_rate_flat
```