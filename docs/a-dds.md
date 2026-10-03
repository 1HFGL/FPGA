# A：单声部 DDS 交付说明

更新：本文描述 A 的单声部接口；2026-09-30 的四实例集成、力度/简单包络和布局布线另见 [ABC demo](abc-demo.md)，不要把下文旧阶段限制当成整合版本状态。

本阶段完成直接数字合成（DDS）：相位累加器按采样使能推进相位，取高 10 位访问一个周期的正弦波表，输出 16 位有符号音频样本。
当前只有单声部正弦波；音符编号查表、ADSR、力度、多声部和多音色待开发。联合顶层已通过高云综合，但这不等于时序或实物验证。

## 文件布局

- `rtl/phase_acc.v`、`rtl/wave_lut.v`、`rtl/voice_dds.v`：可综合设计源码。
- `rtl/rom/sine_1024.mem`：必须提交的 ROM 初始化数据，不是仿真缓存。
- `sim/tb_*.v`：A 的三个测试平台；原有 B 测试文件保持不变。
- `sim/run_tests.ps1`：可配置工具目录的批量测试入口，支持 A、B、All。
- `sim/run_phase_acc.do`、`sim/run_wave_lut.do`、`sim/run_voice_dds.do`：交互式波形入口，共用 `sim/a_common.tcl`。
- `model/gen_sine.ps1`：生成波表；`model/check_dds.py`：Python 3 标准库参考核对。
- `results/logs/`、`results/waves/`、`results/*_work/`：运行产物，不提交。

## 接口与时序

入口为 `voice_dds`。所有输入均要求与 `clk` 同步，不包含跨时钟处理。

| 信号 | 定义 |
| --- | --- |
| `clk` | FPGA 主时钟；不是声音频率 |
| `rst` | 高电平同步复位，在上升沿优先清零相位和输出，valid 为 0 |
| `sample_tick` | 上升沿采到 1 就接受一个采样请求；连续为 1 表示每拍都有请求 |
| `phase_inc[31:0]` | 无符号相位增量；每个请求推进一次，32 位溢出自然回绕 |
| `sample[15:0]` | 有符号补码 PCM 值；没有请求时保持 |
| `sample_valid` | 在接受请求的上升沿之后与 sample 同时更新；无请求的上升沿后变为 0 |

ROM 在请求沿读取更新前的相位，因此复位后第一次输出为 0。相位寄存器在该沿之后已前进，波形窗口中当前地址对应下一次读取位置。
另一个在同一上升沿采样的时序模块读到的是旧 sample/valid，新结果可在下一上升沿接收。不要在组合路径上混淆请求与有效输出。
音高改变只改变随后累加的步长，不自行清零相位；相位连续不等于所有控制切换都已做听觉平滑。

48 kHz 是当前设计/测试约定，并非实测硬件参数：
`phase_inc = round(f_note * 2^32 / 48000)`。
440 Hz 使用 39370534，880 Hz 使用 78741067。实际采样率改变时必须重算增量。

## 与 B 对接

- B 的 `sample_request` 对应 A 的 `sample_tick`；A 的 `sample` 对应 B 的 `sample_data`；连接 `sample_valid`。
- 使用同一个主时钟，不把 sample_request 当成新时钟。
- B 使用低有效复位且内部同步释放；A 使用高有效同步复位。单音联合顶层使用 B 的 `audio_ready` 反相后驱动 A 的同步复位，详见 [联合说明](ab-single-tone.md)。
- B 的发送器在帧边界使用之前缓存的样本，本次请求产生的样本供后续帧使用。需联合验证首帧静音、欠载标记、取数时刻和中途复位。
- 当前单声部输出接近满幅。混音/音量/包络尚未实现；后续的单音联合仿真和高云综合已完成，但没有布局布线或上板。

## 批量测试（PowerShell）

从仓库根目录执行。`-ModelSimBin` 指向你自己的安装目录，也可以设置 `MODELSIM_BIN` 或将 vsim.exe 加入 PATH。

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'D:\modelsim1\win64'
```

其中 D 盘路径只是本机示例，组长可以传入自己的路径。仅验证 A 时使用 `-Suite A`，B 原有回归使用 `-Suite B`。
脚本自动定位仓库，从其他工作目录使用完整脚本路径启动也可以。
它不仅检查进程退出码，还检查 Fatal/Error 和完整 PASS 标记，避免 ModelSim 报错但退出码为 0 时误判成功。

Python 3 参考核对（先完成包含 A 的批量测试）：

```powershell
python model/check_dds.py
```

Python 不参与最终发声，且不需要第三方包。检查波表和 ModelSim 导出的 4810 个有效样本；复位记录清零参考相位，按相同地址截取、舍入、补码和回绕规则逐项比较。测试平台另行逐主时钟检查 idle/valid，Python 记录只包含复位和有效请求。

## ModelSim 交互式波形

在 Transcript 使用 **source**，不是 **do**。这里使用标准 Tcl source，让脚本可靠获取自身路径，避免之前的 info script 路径问题。

```tcl
source {C:/Users/Nanji/Documents/GitHub/FPGA/sim/run_voice_dds.do}
```

此处改为你克隆仓库的实际位置即可；脚本内部不含个人路径。另外两个入口同样使用 source。
切换工作目录可能提示关闭旧 Project，确认后不删除任何源文件。仿真暂停于 $stop 是预期行为。
若宏暂停导致没有自动缩放，可手动执行 `wave zoom full`；DDS 建议用 `wave zoom range 0ns 10000000ns` 观察前 10 ms。
观察 880 Hz 区间可用 `wave zoom range 60000000ns 70000000ns`。DDS 测试名义主时钟 12 MHz、每 250 拍请求一次，即 48 kHz。

## 波表生成和工程迁移

```powershell
.\model\gen_sine.ps1
```

无论当前目录在哪里，默认写入仓库的 `rtl/rom/sine_1024.mem`；支持 `-OutputPath` 生成到其他位置用于比较。
公式是 `round(32767 * sin(2*pi*k/1024))`，四舍五入采用半值远离零，负数保存为 16 位补码。
RTL 默认 ROM_FILE 为 `rtl/rom/sine_1024.mem`，按仿真进程工作目录解析；提供的入口均固定到仓库根目录。
现有 [高云工程](../fpga_project/README.md) 通过 Include Path `..` 找到波表；本机 GowinSynthesis 已识别 1 个 pROM。换工程或改变目录结构时仍须重新核对路径，板上初始化数据尚未验证。

## 现有限制

原根目录 `run_modelsim.ps1` 仍是旧练习入口，默认引用本仓库未提供的 `rtl/dds_sine.v`；原 B 脚本也有其作者电脑的安装路径。此次 A/回归请使用上面的新入口，避免改变组长原有工作方式。
测试记录见 `docs/a-dds-validation.md`。迁移保留桌面实验原件；后续团队开发以仓库内文件为准。
