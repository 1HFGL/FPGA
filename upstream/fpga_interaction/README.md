# Tang Mega 60K C 部分：交互与声部管理

> 2026-10-14 演奏控制更新：加入独立起音序号、来源隔离、尾音保留、八度松键匹配、
> 延音与来源清理，修复时间戳回绕抢占；事件队列溢出会报告故障并释放本地输入。
> 独立 C 回归17项；联合夹具的8项结果保留在原成果提交，不混入当前主A/B工程。
> 最新接口、实际验证和剩余工作见 [演奏控制阶段说明](doc/c_control_progress_20261014.md)。
> 主13键顶层/约束已在仓库根目录实现，见[接线说明](../../docs/keyboard-wiring.md)。本独立C与主钢琴的功能对接及实物验证仍待完成。
> master中的C入口与运行方式见[C输入说明](../../docs/c-input.md)。

> 2026-10-12 阶段更新：ADS1115双旋钮已修复有符号读数、3.3V量程映射、
> NACK故障处理及平滑响应，12项C测试与2项联合测试通过。
> 最新效果、验证结果和待补信息见 [阶段清单](doc/c_progress_20261012.md)，
> 旋钮接口约定见 [驱动说明](doc/ads1115_driver.md)。
> H19/H20的实物引出及电平仍待核对，旧接线描述和历史impl位流不作为新版本接线依据。

> 同日追加：琴键与音色键默认消抖由5ms缩短为2ms，新增50MHz默认参数测试。
> 更新后13项C测试及2项联合测试通过，详细说明见 [输入层说明](doc/c_input_upgrade.md)。
> 按键板级位流需要重新编译、下载后才生效。

本工程对应分工中的 **C：交互与声部管理**，目标是完成：

```text
按键/触摸输入
  -> 同步与去抖
  -> 按键/触摸接口
  -> 压力/力度接口
  -> 按键事件编码
  -> 32 声部分配、释放、重触发和抢占
  -> 输出给 A 部分进行波形合成
```

本工程已经通过 ModelSim 10.6e 的五套自检测试：

- `tb_input_sync_debounce`
- `tb_pressure_if`
- `tb_event_encoder`
- `tb_voice_allocator`
- `tb_interaction_top`

## 1. 数据流

```text
Key_in[1:0]
   |
   v
touch_or_key_if
   |
   +--> key_level / key_press / key_release
   |
pressure_raw / pressure_valid
   |
   v
pressure_if --> pressure_velocity / pressure_active
   |
   v
event_encoder
   |
   +--> note_on / note_off
   +--> note[6:0]
   +--> velocity[6:0]
   +--> timbre[3:0]
   |
   v
voice_allocator
   |
   +--> voice_active[31:0]
   +--> voice_gate[31:0]
   +--> voice_note_flat[223:0]
   +--> voice_velocity_flat[223:0]
   +--> voice_timbre_flat[127:0]
```

## 2. 模块说明

| 文件 | 功能 |
|---|---|
| `rtl/input_sync_debounce.v` | 两级同步、计数器去抖、按下/松开启边沿检测 |
| `rtl/touch_or_key_if.v` | 多路按键同步去抖，当前板级使用 2 路 |
| `rtl/pressure_if.v` | 压力数据一阶滤波、力度换算和有效判断 |
| `rtl/event_encoder.v` | 将按下/松开状态编码为 note_on/note_off 事件 |
| `rtl/voice_allocator.v` | 32 声部分配、释放、同音重触发和抢占 |
| `rtl/interaction_top.v` | C 部分内部集成顶层，便于后续接 A 部分 |
| `rtl/board_top.v` | Tang Mega 60K 板级测试顶层，连接按键和 LED |

## 3. 当前板级映射

板级顶层为 `board_top`，器件选择信息为：

```text
Device Family : GW5AT-60B
Part Number   : GW5AT-LV60PG484AC1/I0
Package       : PBGA484A
Device Version: B
```

引脚来自 Sipeed 官方 `tang_mega_60K_pins.cst`：

| 信号 | 引脚 | 说明 |
|---|---:|---|
| `sys_clk` | V22 | 50 MHz 系统时钟 |
| `sys_rst_n` | AA13 | 低有效复位/用户按键 |
| `Key_in[1]` | Y12 | 用户按键，低有效 |
| `Key_in[0]` | AB13 | 用户按键，低有效 |
| `LEDs[0]` | T18 | LED 0 |
| `LEDs[1]` | R18 | LED 1 |
| `LEDs[2]` | R17 | LED 2 |
| `LEDs[3]` | P16 | LED 3 |

> `LEDs[4:7]` 没有使用。在 `GW5AT-60B/PBGA484A` 版本 B 上，这几个位置默认是 CPU 专用引脚，直接做普通 IO 会导致布局布线报 `PR2017/PR2028`。

`sys_rst_n` 同时被用作复位，所以当前板级示例实际测试 `Key_in[0]` 和 `Key_in[1]` 两路输入。

LED 极性通过 `board_top` 参数控制：

```verilog
parameter integer LED_ACTIVE_LOW = 0
```

如果板上的 LED 显示相反，把工程里的该参数改为 `1` 即可，不需要改逻辑。

## 4. 板级 LED 含义

`board_top` 当前显示：

```text
LEDs[0] = Key_in[0] 去抖后的按键状态
LEDs[1] = Key_in[1] 去抖后的按键状态
LEDs[2] = 当前有活跃声部
LEDs[3] = 历史最大声部数达到 4
```

按下 `Key_in[0]` 后，预期：

- `LEDs[0]` 点亮；
- 有活跃声部后 `LEDs[2]` 点亮；
- 松开后 `LEDs[0]` 和 `LEDs[2]` 熄灭。

## 5. ModelSim 仿真操作

已提供两个入口。

### 方式一：运行 PowerShell 脚本

双击或执行：

```text
scripts/run_modelsim.bat
```

它会调用：

```text
scripts/run_modelsim.ps1
```

并依次编译和运行五套测试。

### 方式二：在 ModelSim 中手动运行测试

打开 ModelSim，工作目录设为：

```text
D:\AI tools\Codex&GPT\files\fpga_interaction\sim
```

先编译全部文件：

```tcl
do compile_all.do
```

再选择一个测试运行，例如：

```tcl
vsim work.tb_voice_allocator
add wave -r /*
run -all
```

需要运行其他测试时，只需替换 `tb_voice_allocator`：

```text
tb_input_sync_debounce
tb_pressure_if
tb_event_encoder
tb_voice_allocator
tb_interaction_top
```

完整五套测试推荐直接运行 `scripts/run_modelsim.bat`，它会为每个测试启动独立的 ModelSim 进程，避免 `$finish` 提前结束批量脚本。

五套测试期望看到：

```text
PASS: tb_input_sync_debounce press=1 release=1
PASS: tb_pressure_if filtered=4000 velocity=121
PASS: tb_event_encoder on=2 off=2
PASS: tb_voice_allocator active=3 gate=3
PASS: tb_interaction_top key/LED path and voice allocation
```

## 6. 用 Gowin EDA 打开和编译

Gowin EDA 路径：

```text
D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_ide.exe
```

工程文件：

```text
D:\AI tools\Codex&GPT\files\fpga_interaction\tang_mega_60k_interaction.gprj
```

操作顺序：

1. 打开 `gw_ide.exe`。
2. 选择 `File -> Open Project`。
3. 打开 `tang_mega_60k_interaction.gprj`。
4. 确认器件是 `GW5AT-60B`、`PBGA484A`、版本 `B`。
5. 确认顶层模块是 `board_top`。
6. 在工程中确认 `.cst` 和 `.sdc` 已经启用。
7. 先运行 `Synthesize`。
8. 再运行 `Place & Route`。
9. 查看 `Timing Analysis`。
10. 生成 `.fs` 文件。
11. 打开 Gowin Programmer 下载到 SRAM。

如果工程路径中的空格或 `&` 导致 IDE 异常，把整个 `fpga_interaction` 目录复制到不带空格和特殊字符的路径，例如：

```text
D:\fpga_interaction
```

然后重新打开 `.gprj`。

## 7. Gowin Programmer 下载

Programmer 路径：

```text
D:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer.exe
```

操作顺序：

1. 连接开发板。
2. 确认板卡已经按手册要求上电。
3. 在 Programmer 中扫描 JTAG。
4. 选择生成的 `.fs` 文件。
5. 先选择 SRAM 下载。
6. 观察两个用户按键和 LED 的状态。
7. 功能稳定后再烧录 Flash。

## 8. GAO 调试

板上现象不对时，用 Gowin Analyzer Oscilloscope 抓这些内部信号：

```text
u_interaction_top/u_key_if/g_key[0].u_debounce/sync_q
u_interaction_top/u_key_if/g_key[0].u_debounce/stable
u_interaction_top/u_key_if/g_key[0].u_debounce/press_pulse
u_interaction_top/u_key_if/g_key[0].u_debounce/release_pulse
u_interaction_top/u_event_encoder/event_valid
u_interaction_top/u_event_encoder/event_type
u_interaction_top/u_event_encoder/event_note
u_interaction_top/u_voice_allocator/voice_active
u_interaction_top/u_voice_allocator/voice_gate
```

排查顺序：

1. 原始按键信号是否进入 FPGA；
2. 同步后的信号是否稳定；
3. `press_pulse` 是否只出现一次；
4. `event_valid` 是否只产生正确数量的事件；
5. `voice_active` 和 `voice_gate` 是否按预期变化。

## 9. 与 A 部分的接口

`interaction_top` 输出给 A 部分的接口为：

```text
voice_active[31:0]
voice_gate[31:0]
voice_note_flat[223:0]      // 32 x 7 bit
voice_velocity_flat[223:0]  // 32 x 7 bit
voice_timbre_flat[127:0]    // 32 x 4 bit
```

每个声部的数据切片：

```text
voice_note_flat[7*i +: 7]
voice_velocity_flat[7*i +: 7]
voice_timbre_flat[4*i +: 4]
```

A 部分可以使用 `voice_gate` 驱动 ADSR：

```text
voice_gate[i] = 1 -> 进入 Attack/Decay/Sustain
voice_gate[i] = 0 -> 进入 Release
```

当 A 部分的 Release 完成后，把对应的 `release_done[i]` 置 1，通知 `voice_allocator` 真正释放该声部。

当前板级测试为了不接 A 部分也能释放声部，设置：

```verilog
.release_done(4'b1111)
```

正式联调时应改为 A 部分输出的 `release_done`。

## 9.1 32 声部升级

32 声部升级的完整说明见：

``text
D:\AI tools\Codex&GPT\files\fpga_interaction\doc\upgrade_32voice.md
``n

## 10. 这次 Gowin 报错的修复说明

如果出现：

```text
ERROR (PR2028): The constrained location is useless in current package
ERROR (PR2017): 'LEDs[4]' cannot be placed according to constraint
```

原因不是 Verilog 语法，而是：

```text
GW5AT-60B / PBGA484A / 版本 B
T21、R19、P19、U21 等位置属于 CPU 专用引脚
```

当前工程已经改成只使用：

```text
LEDs[3:0]
```

并通过 ModelSim 重新回归。修复后需要在 Gowin 中：

1. 执行 `Project -> Clean`；
2. 重新运行 `Synthesize`；
3. 重新运行 `Place & Route`；
4. 确认 Message 窗口没有 `PR2017/PR2028`；
5. 再生成 `.fs`。

同时修复了综合日志中的：

```text
Undeclared symbol 'event_ready'
```

现在 `interaction_top` 中已经显式声明了 `wire event_ready`。

## 11. 当前限制和下一步
当前已经完成：

- 2 路按键同步去抖；
- 按键到 note_on/note_off 事件编码；
- 32 声部分配；
- 同音重触发；
- 满 32 声部后的最老声部抢占；
- 压力接口的独立仿真；
- 按键到声部分配的板级集成顶层；
- ModelSim 自动测试。

下一步需要根据实际硬件继续完成：

1. 接入第三路用户按键；
2. 接入触摸控制器；
3. 接入板载 ADC 或外部压力传感器；
4. 根据实际按键力度修改 `event_encoder` 的 velocity 来源；
5. 接入 A 部分的 `release_done`；
6. 根据 A 部分的最终接口调整 voice 总线格式；
7. 在 Gowin GAO 上完成板上验证。
## 12. 最新 Codex 升级内容

新增和修改：

```text
rtl/event_encoder.v
rtl/voice_allocator.v
rtl/interaction_top.v
rtl/board_top.v
rtl/reset_sync.v
rtl/voice_test_pattern.v
rtl/board_test_top.v
tb/tb_event_encoder.sv
tb/tb_voice_allocator.sv
tb/tb_interaction_top.sv
tb/tb_voice_test_pattern.sv
```

主要变化：

- event 增加 `source_id`；
- 每个按键支持独立 velocity；
- expression 更新优先按 `source_id` 匹配；
- 新增 32 声部自动测试源；
- 新增 reset synchronizer；
- 普通演奏顶层为 `board_top`；
- 32 声部测试顶层为 `board_test_top`；
- 新增 `tb_voice_test_pattern`。

运行完整测试：

```powershell
D:\AI tools\Codex&GPT\files\fpga_interaction\scripts\run_modelsim.bat
```
