# C 输入阶段成果（2026-10-12）

> 2026-10-13路径维护：本页功能状态、资源／时序数字、日志与哈希仍对应原记录日期，不代表当前版本的新验收。可复用的主工程命令已改用新目录；新运行结果写入 `build/`，不覆盖历史证据。当前工程及完整验证入口见 [目录迁移说明](repository-layout.md) 与 [README](../README.md)。

本分支以 master 的 e7dd27a 为基础提交两组已授权成果。
主工程源码、测试和示例工程分别位于 `rtl/`、`verification/tb/` 和 `projects/`。
独立目录 upstream/fpga_interaction/ 保存本地 C 工程，避免不同接口版本互相覆盖。
upstream/fpga_a/、upstream/fpga_b/ 是联合仿真所需的本地团队源码快照，本次没有修改其核心算法；
upstream/fpga_ab_sim/ 使用这些明确的依赖复现 C+A+B 测试，不代表已接入根目录硬件演示。

阶段一修复 ADS1115 有符号映射、3.3V 端点、ACK 检查、掉线恢复、预热/超时和滤波。
阶段一保持 5ms 默认按键消抖，C 回归为 12 项，联合仿真为 4/32 声部两项。
测试入口为 upstream/fpga_interaction/scripts/run_modelsim.ps1 和 upstream/fpga_ab_sim/scripts/run_modelsim.ps1，
这些上游脚本原样保留，仍使用其作者的 `D:/Modelsim/win64` 和原测试语言设置；不把它们当作主工程当前验证入口，也不声称迁移后已重跑。主工程严格Verilog验证入口见 [目录迁移说明](repository-layout.md)。
旋钮验证工程及实际报告见 upstream/fpga_interaction/verification/knob_20261012/。
Gowin 脚本改为相对自身路径打开工程，避免依赖上传者的工作目录。

H19/H20 仍为未确认的外设接线，保留的 CST 只用于复现现有逻辑验证。
没有上传位流、工作库或大批构建缓存。ADC 固定转换等待、时钟布线警告、
声部重触发、时间戳回绕、13 键实际接入、统一顶层及上板延迟仍需后续处理。
详见 [阶段清单](../upstream/fpga_interaction/doc/c_progress_20261012.md)。

## 阶段二：默认消抖 2ms

独立 C 工程中四层默认值由 250000 改为 100000（50MHz）；联合顶层为 CLK_HZ/500。
新增默认 50MHz 测试，按下和松开均为 2.00005ms，毛刺和分段抖动没有多余事件。
更新后 C 13 项、联合仿真 2 项通过；日志见
upstream/fpga_interaction/verification/debounce_2ms_20261012/。
这不是整机声音延迟的测量，也不改变 root rtl/ 下原 ABC 演示的消抖或接口。
按键位流尚未重新构建/下载，实际模块抗抖效果待验证。
