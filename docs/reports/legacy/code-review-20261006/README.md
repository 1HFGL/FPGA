# 2026-10-06 代码审查与优化证据

本轮在 `codex/adsr-integration` 的A最新代码与既有B/C未提交集成成果上，修复四项分配器问题并减少资源。详见 [审查报告](../../docs/code-review-20261006.md)。此目录为当前版本证据；当天上午 `poly-integration-20261006` 为优化前基线。

- `baseline/voice_allocator.v`：审查前源码，仅用于独立工作库复现，不加入正式高云工程。
- `tb_allocator_*_before.log`：四个原缺陷的实际失败记录；`tb_allocator_age_after.log` 是第一步修复后的阶段检查。最终结果以同名不带后缀日志及All清单为准。
- `all_console.txt`、26个正常测试日志：ModelSim SE-64 10.6e完整回归通过，保留旧版与新版ADSR测试。
- `python_references.txt`：Python 3.12.14五个参考程序通过，包含新bank默认38379／边界2721样本及旧bank61097样本。
- `negative_console.txt`、`tb_instrument_adsr_negative.log`：10530ns受控串行错误非零拒绝，属于预期失败。
- `All_sha256.txt`、`ADSRDemo_negative_sha256.txt`：正常及负向测试对应的源码身份。
- `gowin_manual_console.txt`、`gowin_auto_console.txt`、两套资源／时序报告：Gowin V1.9.12.04实际综合、布局布线、位流生成。
- `artifacts_sha256.txt`：工程、约束、脚本、参考模型、报告及位流身份；`.fs`在本机，未上传。
- `review_baseline_sha256.txt`：原缺陷复现用源码、测试平台和运行宏的身份。
- `rollback/`：审查前文件和位流的本机恢复副本，忽略上传；原有stash保留。

普通版 LUT/ALU/寄存器为2119/576/965，自动版2847/572/803；两版均4个BSRAM、8个DSP。50MHz下Setup/Hold违例0/0，最差裕量普通+6.619/+0.125ns、自动+5.669/+0.123ns。8/8端口有物理约束；PR1014非专用输入时钟路由、完整DAC外部时序、功放启动及整机延迟仍待验证。位流生成不等于上板通过。

本轮未烧录、未测实物、不勾选赛题验收。可复现命令及剩余问题见审查报告。
