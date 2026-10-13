# 四声部 ADSR：50 MHz 综合与布局布线验证

> 2026-10-13路径维护：本页功能状态、资源／时序数字、日志与哈希仍对应原记录日期，不代表当前版本的新验收。可复用的主工程命令已改用新目录；新运行结果写入 `build/`，不覆盖历史证据。当前工程及完整验证入口见 [目录迁移说明](repository-layout.md) 与 [README](../README.md)。

日期：2026-10-03。A 分支 `feat/a-dds-core`，基础提交 `57e17d6`，包含此前尚未提交的四声部实现。实际使用 Gowin V1.9.12.03 (64-bit)、GW5AT-LV60PG484AC1/I0 和 **20 ns / 50 MHz** 时钟约束。

**四声部核心及同钟接口路径均通过本次独立实现时序检查。** 较完整的同钟接口验证结果为 Setup **+7.341 ns**、Hold **+0.247 ns**，违例均为 0。没有放宽时钟周期或添加 false/multicycle path；核心 RTL、默认参数和 R3 输出延迟未修改。

## 两份实际报告

| 项目 | 裸核心 `voice_bank_adsr` | 同钟接口验证外壳 |
|---|---|---|
| 报告时间（本机） | 20:13:55 | 20:18:33 |
| 最差 Setup 裕量 | +7.743 ns | **+7.341 ns** |
| 最差 Hold 裕量 | +0.247 ns | +0.247 ns |
| Setup / Hold 违例端点 | 0 / 0 | 0 / 0 |
| Setup / Hold 总负裕量 | 0 / 0 ns | 0 / 0 ns |
| 最小脉宽裕量 | +7.391 ns | +7.391 ns |
| 工具估算 Fmax | 81.583 MHz | 78.994 MHz |
| 已分析路径 / 端点 | 4311 / 2070 | 2635 / 2541 |
| LUT / ALU | 2454 / 558 | 2526 / 558 |
| 寄存器 | 577 | 734（包含外壳） |
| BSRAM / DSP | 4 / 8 | 4 / 8 |

默认配置 A=96、D=24000、S=6554、R=5760、`MIX_SHIFT=5`；ROM 为 `rtl/rom/sine_1024.mem`。综合与布局布线日志均无 WARN/ERROR，四路独立相位/包络、四个 pROM 和八个乘法单元保留；没有因读取 ROM 失败而删除声部。默认缩放保证总和不溢出，`sample_clipped` 被优化为常量 0 是正常结果。

接口外壳最紧路径仍在声部 3（第四个声部）的包络：`env_level_3_s0/Q` 到 `env_level_12_s0/D`，11 层逻辑；路径表的数据延迟为 12.610 ns。当前结果已留出几 ns 的 Setup 余量；Hold 属于最小延迟检查，不能要求它与 Setup 留出相同的几 ns。

## 为什么增加验证外壳

裸核心的 SDC 只有 `create_clock`，能检查内部寄存器、ROM、DSP 之间路径，但输入端的音符查表等组合逻辑缺少发射时钟。因此额外建立 `voice_bank_adsr_timing_top`：在同一 `clk` 域为所有输入和输出增加寄存器，模拟 C 的同步控制输出与 B 的同步采样接口。

外壳保留 66 个输入寄存器和 91 个输出寄存器，全部使用同一个时钟。音频高四位共享符号寄存器，恒为零的饱和标志不需寄存器。总寄存器数相较裸核心增加 157，与映射网表一致。报告实际包含音符寄存器网络，例如 `note_q[23]` 的 Worst Slack 为 +11.333 ns，确认查表相关路径参与检查。

外壳只用于实现验证，额外输入、输出各一拍，不接入乐器发声链路。生产核心仍在请求 R0 后的 R3 输出，B/C 接入时继续使用[四声部接口说明](a-poly-adsr.md)。两份报告布局不同，不能通过直接相减路径数量判断遗漏；共同核对了单一有效时钟、同钟寄存器边界、无时序例外和完整声部资源。

## 可重复运行的工程

独立工程放在 [projects/checks/poly_adsr_check](../projects/checks/poly_adsr_check/)，与团队原来的工程分开。包含九份 RTL 引用、验证外壳、20 ns SDC、设置文件和执行脚本。所有 RTL 路径相对仓库，ROM 搜索路径由脚本定位；队友不需修改代码中的 ROM 参数为个人绝对路径。

在本机仓库根目录的 PowerShell 中执行（队友按实际工具安装路径调整）：

```powershell
& 'C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' '.\projects\checks\poly_adsr_check\run.tcl'
```

历史版本已在仓库根目录使用迁移前路径实际复现，报告时间为 Sat Oct  3 20:29:11 2026；Setup/Hold、违例、脉宽和 Fmax 与上表一致。此工程的本机 `impl/` 已有最新结果，另存 [仓库工程复现报告](reports/poly_adsr_timing_20261003/repository_reproduction/timing.html)。

运行后可在高云软件打开 `projects/checks/poly_adsr_check/poly_adsr_check.gprj`，查看 Process → Place & Route → Timing Analysis Report。该工程的顶层是 **voice_bank_adsr_timing_top**；团队原工程的顶层保持原状。重新运行产生的 `impl/` 报告属于本次本机结果，布局可能略有差异，应以新报告为准。

脚本会把随工程保存的设置复制到该独立工程的生成目录，启用同单声部验证一致的 hold 修复及 timing-driven 布局，再进行综合/布局布线。验证外壳也实际通过 Verilog-2001 编译；旧音符查表仅有继承 timescale 的非功能警告。核心源码哈希与此前 19 项功能回归时一致，因此本轮未重复整套功能仿真；此前默认/边界共 41100 个样本对照证据见[功能验证目录](reports/poly_adsr_20261003/)。

## 原始证据与范围

- [同钟接口时序报告](reports/poly_adsr_timing_20261003/registered/timing.html)、[资源报告](reports/poly_adsr_timing_20261003/registered/place_route.txt)。
- [裸核心时序报告](reports/poly_adsr_timing_20261003/core/timing.html)、[资源报告](reports/poly_adsr_timing_20261003/core/place_route.txt)。
- [运行条件、源码和报告 SHA-256](reports/poly_adsr_timing_20261003/manifest.json)。两套综合/P&R/控制台日志、实际设置与 SDC 同目录保存。

原始工程/脚本快照包含本机临时路径，仅用于审计；重新构建请使用上面的可移植独立工程。裸核心第一次运行时，控制台出现无法写入软件全局 `sh.log` 缓存的提示；其独立综合/P&R 日志与最终报告完整，命令退出 0。接口验证运行允许软件写入自身缓存后，无此提示，完整构建退出 0。

两套 SDC 均只激活一个 20 ns 时钟，没有路径例外。报告未给出未约束路径总数；Recovery/Removal 显示无可报告路径。本次没有 CST 或外部输入/输出延迟约束，工具自动分配的 162 个端口是独立实现所用，不是乐器实际接线。**不能把生成的验证 bitstream 下载到板卡。**

结论仅覆盖本次默认参数下的四声部核心和同钟寄存器接口。实际 B/C 的组合逻辑、缓存、复位同步、板级引脚、DAC 外部时序及上板试听仍需集成后验证；其他包络参数和混音配置也应各自检查实现时序。本次没有改动团队顶层或板级约束，没有下载硬件、Git 提交或推送，也不勾选整机实物验收项。

下一步与 B/C 核对独立触发、`release_done` 反馈、R3 输出/R4 读取，再接入团队顶层并重跑整机功能与时序。
