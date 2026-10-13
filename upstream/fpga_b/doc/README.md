# FPGA B：采样节拍和 I2S 仿真模型

本目录是 B 部分的服务于 C 仿真的简化实现。

## RTL

- `rtl/sample_tick_gen.v`：根据系统时钟和采样率产生 sample_tick。
- `rtl/i2s_tx.v`：将并行音频样本串行化，产生 bclk、lrck 和 sdata。

默认目标参数：

```text
系统时钟：50 MHz
采样率：48 kHz
```

联合仿真时使用较低频率以缩短仿真时间。