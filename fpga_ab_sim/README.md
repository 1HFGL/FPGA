# C + A + B 联合仿真工程

2026-10-14：新增八度、延音、来源清理和起音/完成序号，联合侧共 8 项回归通过。
包括原 4/32 声部系统测试、16 声部重触发测试、4 种声部数量的混音参考测试及音频流水级测试。
接口合同与待完成硬件事项见 [C 演奏控制阶段成果](../fpga_interaction/doc/c_control_progress_20261014.md)。

本工程把：

```text
C：interaction_top
A：synth_engine
B：sample_tick_gen + i2s_tx
```

连接成完整闭环：

```text
按键/测试事件
  -> C 声部分配
  -> A 实时合成
  -> A release_done
  -> C 释放声部
  -> B sample_tick
  -> B I2S 输出
```

## 运行

双击：

```text
scripts\run_modelsim.bat
```

或者执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\AI tools\Codex&GPT\files\fpga_ab_sim\scripts\run_modelsim.ps1
```

期望结果：

```text
PASS: tb_c_ab_system voices_reached=4 audio=1 i2s_edges=...
```

测试内容：

- C 自动启动 4 个声部；
- A 输出非零音频样本；
- B 输出 sample_tick 和 I2S 波形；
- A 的 release_done 让 C 释放声部。
## 32 声部联合测试

新增：

```text
tb/tb_c_ab_system_32.sv
```

它会验证：

- C 同时分配 32 个声部；
- A 合成非零音频；
- B 产生采样节拍和 I2S 波形；
- A 的 release_done 能让 C 释放全部声部。

当前结果：

```text
PASS: tb_c_ab_system_32 voices_reached=32 audio=1 i2s_edges=15001
```
