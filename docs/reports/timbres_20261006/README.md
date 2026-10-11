# 两种音色验证证据：2026-10-06

基于 `c8286e2f05fc4d02130b2b2dea7286b85b30143c` 的工作区改动；本轮没有执行 Git commit/push。完整说明和复现命令见 [两种音色接口](../../a-timbres.md)。

- `simulation/all/`：ModelSim 22 项完整回归原始日志；完整运行在隔离目录完成。
- `simulation/All_sha256.txt`：完整回归输入，归档时全部与正式仓库逐一校验相同。
- `simulation/timbre_repo_console.log`、`timbre_repo_python.log`：正式仓库路径重跑三项新仿真、独立模型和综合网表核验。
- `simulation/python_references_20261006.log`：七个 Python 检查入口的实际输出。
- `simulation/timbre_gui_smoke_console.log`：ModelSim 波形脚本执行证据。
- `simulation/timbre_checker_negative.log`：四种损坏／截断轨迹均被拒绝；输入来自专项 Icarus 运行。
- `simulation/timbre_netlist_audit.json`：8192 ROM 字、64 选择位及动态选择连接检查，解释四条层级优化警告。
- `timing/`：正式仓库 15:46:32 生成的综合、布局布线与时序原始报告；50 MHz，Setup +7.553 ns，Hold +0.190 ns，违例 0／0。
- `audio/`：真实 RTL 输出的柔和／明亮 WAV 各 1 秒；共同放大 8 倍、无削波，JSON 保存参数、频谱和哈希。这不是实物录音。
- `source_sha256.txt`、`trace_sha256.txt`、`summary.json`：代码／构建输入、四份正式采样轨迹的哈希及验证范围。

未修改 B/C 集成顶层，未下载硬件、未完成板级 I/O 和整机时序验收。该独立高云外壳无板级 CST，不能作为可下载整机。

大体积 trace/WLF 不纳入此目录，按说明可重建。生成工具的路径和时间戳原样保留；时序 HTML 保存的是内容页，锚点可在本页查看。
