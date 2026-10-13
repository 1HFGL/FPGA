# A DDS 迁移验证记录

> 2026-10-13路径维护：本页功能状态、资源／时序数字、日志与哈希仍对应原记录日期，不代表当前版本的新验收。可复用的主工程命令已改用新目录；新运行结果写入 `build/`，不覆盖历史证据。当前工程及完整验证入口见 [目录迁移说明](repository-layout.md) 与 [README](../README.md)。

日期：2026-09-27。环境：Windows，ModelSim SE-64 10.6e；Python 3 标准库。
分支：`feat/a-dds-core`。本记录对应此次整理后的代码；不是综合、时序或硬件测试报告。

## 复现

仓库根目录：

```powershell
.\verification\scripts\run_tests.ps1 -Suite All -ModelSimBin 'D:\modelsim1\win64'
python model/check_dds.py
```

ModelSim 路径按各自安装位置传入。记录时 Python 使用本机工具运行时的 Python 解释器；未要求队友安装相同位置。

## 实际结果

| 检查 | 实际结果 |
| --- | --- |
| ModelSim 编译 A+B 指定源码 | Errors: 0, Warnings: 0 |
| `tb_phase_acc` | 15 项通过 |
| `tb_wave_lut` | 1035 项通过，覆盖全部 1024 地址 |
| `tb_voice_dds` | 4810 个有效样本匹配，1200025 个时钟检查通过 |
| 440 Hz 过零估频 | 440.165 Hz，通过；采样点定位有量化误差 |
| 880 Hz 过零估频 | 879.965 Hz，通过 |
| B 原有 `sample_tick_tb` | 640 个半边沿、10 帧及复位检查通过 |
| B 原有 `synth_top_tb` | 串行数据、声道、缺样本、功放使能和复位检查通过 |
| Python 独立参考 | 1024 个波表值、4810 个 RTL 样本及 6 条复位记录通过 |
| PowerShell 波表再生成 | 与提交波表逐行一致 |
| 换目录复现 | 复制到另一个包含空格的目录，从不同工作目录通过 Tcl source 运行 DDS 入口，完整采样检查通过 |

全部五个 ModelSim 测试完成后，为新增的可选采样导出重新运行了 A 三项及 Python 核对。B 的源码和测试平台未修改。
换目录检查在 ModelSim 命令行模式运行同一交互入口；波形缩放在 batch 模式不生效，不把这项称为 GUI 视觉验证。

## 证据位置和边界

- 自动生成的运行日志：`build/regression/logs/*.log`；DDS 采样记录：`build/regression/logs/dds_trace.txt`。这些可再生成的文件已忽略，不上传。
- 各测试都有正常、复位和边界检查，原检查条件没有放宽。
- 本次是 A 子模块验证与 B 原测试回归，不是 A 和 B 实际连接后的联合仿真。
- 尚未完成：Gowin 综合、布局布线及时序、板级引脚与 ROM 初始化确认、DAC 实物发声、整机延迟。
