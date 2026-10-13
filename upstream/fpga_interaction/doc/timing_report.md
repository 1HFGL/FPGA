# C 部分时序验证报告（2026-10-08）

工程：fpga_interaction（Tang Mega 60K / GW5AT-LV60PG484AC1/I0，版本 B）
顶层：board_test_top（board_top 参数 TEST_MODE=1，32 声部测试激励）
时钟约束：sys_clk 50 MHz（period 20 ns，见 gowin/tang_mega_60k_interaction.sdc）

## 结论

- 综合、布局布线、静态时序分析、比特流生成全部成功。
- 最差建立时间余量（setup slack）：+7.793 ns（满足）。
- 最差保持时间余量（hold slack）：+0.199 ns（满足，无违例）。
- 关键路径数据到达时间约 16.06 ns，远小于 20 ns 时钟周期，余量充足。
- 资源占用很低：Logic 1275/59904（3%）、Register 1629/60780（3%）、CLS 6%、I/O 8/297。

## 两个必须注意的点

### 1. 旋钮/完整键盘逻辑在本次时序里被综合优化掉了（swept）

因为 board_top 目前把旋钮和其余琴键都“写死”了：

- knob_raw_flat = 0、knob_valid = 1
- 11 个琴键固定为未按下、音色键固定 1

这些逻辑的输入是常量、输出又没接到任何可观测引脚，所以 Gowin 综合时把
adc_knob_if、event_encoder、pressure_if、音色键消抖、以及 11 路按键消抖全部
优化删除（NL0002 “swept” 警告）。

因此：本次时序结果只覆盖“声部分配 + 测试激励”这条活跃路径，
**并没有真正验证旋钮 ADC 通路和完整键盘通路的时序**。
要验证旋钮，必须先把真实 ADC 接线和引脚填进去。

### 2. sys_clk_d 用了普通布线资源（PR1014）

```
WARN (PR1014): Generic routing resource will be used to clock signal 'sys_clk_d'
by the specified constraint. And then it may lead to the excessive delay or skew.
```

含义：派生/缓冲后的时钟 sys_clk_d 没有走全局时钟网络，可能带来额外延迟和偏斜。
目前 hold/setup 仍为正，但不建议忽略。需要在后续把 sys_clk 正确约束到全局时钟资源，
并确认复位/时钟域处理。

## 建议下一步

1. 提供旋钮和键盘的实际引脚方案后，填 board_top 与 .cst，再重新跑一次完整时序。
2. 处理 PR1014：确认 sys_clk_d 是否需要走全局时钟（通常是时钟缓冲/复位同步导致），
   必要时用 BUFG/时钟原语或调整 .sdc。
