# C 输入阶段成果（2026-10-12）

本分支以 master 的 e7dd27a 为基础提交两组已授权成果。
仓库根目录 rtl/、tb/ 和 fpga_project/ 保留团队原有 ABC 演示。
独立目录 fpga_interaction/ 保存本地 C 工程，避免不同接口版本互相覆盖。
fpga_a/、fpga_b/ 是联合仿真所需的本地团队源码快照，本次没有修改其核心算法；
fpga_ab_sim/ 使用这些明确的依赖复现 C+A+B 测试，不代表已接入根目录硬件演示。

阶段一修复 ADS1115 有符号映射、3.3V 端点、ACK 检查、掉线恢复、预热/超时和滤波。
阶段一保持 5ms 默认按键消抖，C 回归为 12 项，联合仿真为 4/32 声部两项。
测试入口为 fpga_interaction/scripts/run_modelsim.ps1 和 fpga_ab_sim/scripts/run_modelsim.ps1，
当前脚本使用 D:/Modelsim/win64 下的 ModelSim；运行联合脚本前从项目根目录调用。
旋钮验证工程及实际报告见 fpga_interaction/verification/knob_20261012/。
Gowin 脚本改为相对自身路径打开工程，避免依赖上传者的工作目录。

H19/H20 仍为未确认的外设接线，保留的 CST 只用于复现现有逻辑验证。
没有上传位流、工作库或大批构建缓存。ADC 固定转换等待、时钟布线警告、
声部重触发、时间戳回绕、13 键实际接入、统一顶层及上板延迟仍需后续处理。
详见 [阶段清单](../fpga_interaction/doc/c_progress_20261012.md)。
