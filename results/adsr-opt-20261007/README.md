# 2026-10-07 ADSR 优化候选与恢复验证

基线为 `d909b17`。试验三种逐点等价算术改写后，没有保留任何生产RTL修改：因子分解收益可忽略，查表资源增加，倒数乘法虽省LUT但增加DSP且时序退步。详见 [试验与取舍](../../docs/adsr-optimization-20261007.md)。

- `factor_trial/`、`table_trial/`、`reciprocal_trial/`：每种试验当时的 `adsr_env.v` 与普通版实现报告。仅为快照，禁止与正式RTL一起编译。
- `factor_*_console.txt`、`table_*_console.txt`、`reciprocal_*_console.txt`：各候选实际包络／算术测试及普通版综合、布局布线过程。前两种包络测试为原10组参数，倒数版及最终恢复版为12组；均含新增65537幅度穷举。
- `arithmetic_baseline_console.txt`：改动前原RTL在新增算术检查下通过。
- `all_console.txt`及27项正式测试日志：原RTL恢复后的完整回归通过。
- `python_references.txt`：最终源码的五个Python参考程序通过。
- `arithmetic_negative_console.txt`、`negative_console.txt`及对应两个负向测试日志：21ns算术观察错误和10530ns串行观察错误被拒绝，是预期失败。
- `All_sha256.txt`、`ADSRMath_negative_sha256.txt`、`ADSRDemo_negative_sha256.txt`：对应运行的源码身份。
- 顶层两套 `.rpt.txt`／`.tr` 和 `gowin_*_console.txt`：恢复原RTL后新生成的普通／自动版报告，不是候选报告。
- `artifacts_sha256.txt`：当前工程、约束、模型、报告及两份重新生成位流的身份；`trials_sha256.txt`记录三个候选快照。
- `rollback/`：本机审查前源码与位流恢复点，忽略上传；原有Git stash未动。

当前普通版LUT/ALU/寄存器为2119/576/965、自动版2847/572/803，均4 BSRAM、8 DSP。50MHz下Setup/Hold违例0/0，普通裕量+6.619/+0.125ns，自动+5.669/+0.123ns。PR1014和完整外部DAC时序风险未解决；没有上板验证，也没有Git提交／推送。
