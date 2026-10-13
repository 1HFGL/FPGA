# 乐器预设工程：采样使能连接审计

2026-10-13，本轮 Gowin 网表把公共采样使能自动网名从 `error_acc_6_7` 改为 `error_acc_6_9`，相关组合逻辑被放入另一层级。旧审计固定匹配名字而失败，不能据此认定 RTL 功能错误，也不能仅删除断言。

修正后的 `model/check_presets_board.py` 以 `u_bank/request_d1_s0.D` 为采样请求锚点，沿实际实例端口解析同一根网，检查 9 个 ROM、波表选择寄存器、力度保护寄存器及 B 的 11 个整帧样本寄存器的使能和时钟连接。原有 9216 字 ROM 内容、两组各 128 项 LUT 真值、8 个引脚、5 条有效 SDC、时序、配置和警告门槛均保留。

## 归档文件与结果

- `normal.json`：实际工程正例通过。最差 setup 为 +5.177 ns，内部 setup 为 +6.776 ns，hold 为 +0.143 ns，最小脉宽余量为 +6.809 ns；保留 PR1014 警告。
- `negative-controls.json`：6 个独立错误副本均经原检查器入口返回退出码 1，且在预期结构断言处拒绝，不是因缺少后续报告而失败；记录检查器和真实网表 SHA-256，并确认真实网表未改动。
- `rom_ce_tied_high.log`、`hierarchy_wave_ce_tied_low.log`、`dac_frame_ce_tied_high.log`、`selector_ce_tied_high.log`、`request_anchor_tied_low.log`、`rom_clock_tied_high.log`：分别保留 ROM 使能接高、层级波表使能接低、DAC 整帧使能接高、选择寄存器使能接高、请求锚点接低、ROM 时钟接高的预期拒绝日志。
- `test_ce_mutations.py`：当轮审计脚本的逐字节归档，不是新增通用构建入口。它使用当轮网表的具体实例/端口，且通过原位置的相对层级计算仓库根目录；**不能直接在本归档目录执行**。如需复现，应放回仓库的 `build/b-review-20261013/presets-ce-audit/test_ce_mutations.py`，使用同一真实网表，在仓库根目录运行 `python build/b-review-20261013/presets-ce-audit/test_ce_mutations.py`。脚本会在该 build 目录产生故障网表副本和结果，不修改生产网表。

正例通用入口为 `python model/check_presets_board.py`，必须先具备该工程当前源码对应的 Gowin 实现结果；过期报告仍会被拒绝。此归档不包含复制网表或工程，不替代实物下载、试听、外部 DAC 接口时序或整机延迟测量。
