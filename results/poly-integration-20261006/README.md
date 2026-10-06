# 2026-10-06 A 最新四声部板级整合证据

基于 `c8286e2` 与本地既有未提交的B/C集成代码，板级顶层实际实例化 `voice_bank_adsr`／`sample_mixer4`。没有提交、推送或操作板卡。完整接口和工具结果见 [接入说明](../../docs/poly-integration.md)。

本轮实际执行：22项ModelSim回归、五个Python参考检查、串行负向检查、普通／自动版Gowin综合及布局布线。正常测试通过；负向测试正确非零拒绝。普通Setup/Hold为+6.271/+0.162ns，自动为+5.534/+0.123ns，50MHz下违例均0/0，8/8端口有引脚约束。PR1014及完整外部DAC时序风险保留，不代表实物或比赛验收。

- `all_console.txt`、各测试 `.log`：本次22项正常运行结果。
- `python_references.txt`：五个参考模型输出。
- `negative_console.txt`、`tb_instrument_adsr_negative.log`：10530ns受控串行错误被拒绝。
- `All_sha256.txt`、`ADSRDemo_negative_sha256.txt`：对应编译源码和波表身份。
- `gowin_manual_console.txt`／`gowin_auto_console.txt`、两套 `.rpt.txt`／`.tr`：本次实现过程、资源、约束和时序报告。
- `artifacts_sha256.txt`：工程、约束、脚本、参考模型、两份新位流和旧渐变位流的SHA256。
- `rollback/`：改动前文件、原10月2日普通／自动位流及本地工作区补丁；本机恢复用途，忽略上传。10月5日具名stash仍保留，未删除用户恢复点。

大体积轨迹和波形位于忽略的 `results/logs/`／`results/waves/`，重新运行可生成。新普通 `.fs` 位于 `fpga_project/impl/pnr/instrument_adsr.fs`；自动版文件名带 `_auto`，勿混用。新版本尚未下载和试听，整机延迟、13键、ADC旋钮、两音色与规则口径仍待验证。
