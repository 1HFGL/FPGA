# 明亮度响应增强（2026-10-24）

基于 master `df0e894009e613dbf34011e63bc05653eb92843e`。AIN2 实体滑块已在该版本接入，显示范围为 0～127。本轮针对“数值变化但听感区别小”改进滤波响应，没有证据证明之前的滑块连线或实际烧录版本存在错误。

## 修改与兼容

原 `tone_filter` 是单级低通，系数为 `2048 + 500 × brightness`，127 旁路；上半段的高频衰减较小。正式 HDMI 现在默认 `ENHANCED_BRIGHTNESS=1`，使用两级低通，0～126 按对数扫动各级的截止频率（400 Hz～12 kHz），127 逐样本恢复原音。两级合起来在最低档的约 -3 dB 点为 257 Hz，各级的 400 Hz 不是整体截止频率。

系数由 `model/brightness_response.py` 生成，明确考虑离散采样的频率响应并量化为 Q16。没有共振增益，没有增加音频延迟 RAM。两级使用同一输入样本对应的控制快照；保留原来每采样一步的平滑、复位清零及有限尾声。

钢琴／吉他合成核心、系数 ROM、双16并行32声部、48 kHz、音量、弯音、KEY1音区、KEY2乐器，以及 Chorus→Delay→Room 顺序保持。AIN2、BLE、USB 及屏幕接线沿用当前 master。USB 主机仍是未通过实物验收的检查点，本轮不把它当作已验收功能。

旧 `tone_filter` 默认保持原算法；兼容核心 `instrument_uart_top` 默认 `ENHANCED_BRIGHTNESS=0`。历史 TB 原文件不改，R955 测试通过显式 `--legacy-brightness` 运行，不冒充当前默认的测试。

## 可重复的响应指标

下表来自 RTL 实际输出与同一输入的频谱比较，单位 dB；三频输入幅度均为4000，避免输入削顶。

| 明亮度 | 约4 kHz，旧版 | 约4 kHz，新版 |
|---|---:|---:|
| 0 | -24.25 | -39.88 |
| 32 | -5.51 | -25.28 |
| 64 | -1.69 | -12.26 |
| 96 | -0.45 | -3.92 |
| 127 | 0 | 0 |

在0档，约258 Hz的衰减由旧版 -3.28 dB 变为新版 -3.02 dB，而高频抑制增强约15.6 dB。因此变化不是简单把整个声音等比例调小。低明亮度仍会降低高音的响度，这是低通滤波的正常结果；音高控制和主音量控制不改变。

## 验证与复跑

在仓库根目录执行；按本机安装位置设置 `$py`、`$ms` 和 `$vendor`。

```powershell
$py='C:/Users/Nanji/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$ms='D:/modelsim1/win64'
$vendor='C:/Gowin/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v'
& verification/scripts/check_verilog.ps1 -ModelSimBin $ms
& $py model/brightness_response.py vectors
& $py verification/scripts/run_final_tests.py tb_brightness_response --bin $ms
& $py model/brightness_response.py analyze
& $py verification/scripts/run_final_tests.py tb_brightness_hdmi --bin $ms --gowin-simlib $vendor
& $py model/brightness_response.py hdmi
& $py verification/scripts/run_final_tests.py tb_controls_meter_hdmi --legacy-brightness --bin $ms --gowin-simlib $vendor
& projects/hdmi/build.ps1 -Python $py -Gowin C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
```

新单元测试覆盖128档、正负满幅、随机输入、控制快照、复位中断、过快请求和有限静音尾声，34816个输出逐个对照独立整数参考。频谱断言要求0档和中间档确实加强高频抑制，而不只是“PCM不相同”。

新集成 TB 使用正式带屏默认参数、真实48 kHz节拍、厂商DPB模型和三通道ADC时序模型；通过AIN2切换0/64/127，覆盖两种乐器、13实体键加19个UART音符填满32槽、第33音抢占、ADC断连恢复、HDMI热插拔和复位。检查完整DAC串行输出；127档与旧滤波的DAC/PA/UART逐拍对照。导出五级样本，分别检查旧滤波、新滤波、Chorus、Delay、Room的整数结果。

当前默认音频缓存由R955变为R958，增加3个50 MHz时钟（60 ns），976拍准备窗保留18拍。这个数字是数字链路调度余量，不是布局布线的Setup余量，也不是整机输入至声音的延迟。

## 后续试听方法

烧录须由用户重新授权，本轮只做离线修改与验证。实物复测时，固定音量和弯音，分别在钢琴、吉他上以相同力度重弹同一个中音，依次比较127、64、0：127应保留原音，64应明显柔和，0应显著压低尖锐泛音。切档后重新起音并留出原效果器尾声衰减时间，避免用上一档残留的回声判断下一档。

再在持续按音时来回移动滑块，确认没有新爆音、卡音或音高变化；两种乐器、低中高三个音区都要复测。仿真已经证明的频谱差异不能替代这项实物试听。
