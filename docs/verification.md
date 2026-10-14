# 验证入口与结果边界

2026-10-14的13键提交（`b59f8ee7`）验证结果：87文件严格Verilog编译，原C7/钢琴2/UART7与新增键盘2项共18项通过，57份原有测试字节保持；23端口指定约束和50MHz布局布线通过，setup/hold +4.519/+0.227ns，4音频pROM、6BSRAM、8.5DSP。CPU引脚GPIO复用已开启，控制配置和生效配置一致。细节与数字观测边界见[13键接线与运行](keyboard-wiring.md)，日志在 `build/keyboard-verification`、`build/regression/keyboard` 和 `build/piano`。
下文“清理后的执行记录”是GitHub `0406c609` 的10月13日基线记录，当前下载入口改为 `piano_13key_top`/`piano_13key.fs`；本轮整理进入master，没有接线、下载或实物验收。

本文维护当前结果，不每轮另建日期MD。生成日志/波形/模型输出写`build/`；必要报告和源码/约束/波表/工具/位流身份一并保存。历史完整证据在Git提交[f513622](https://github.com/1HFGL/FPGA/tree/f513622/docs/reports)，当前目录不重复存放。

## 当前命令

在仓库根执行；其他电脑用`-ModelSimBin`/`-Gowin`指定安装路径。缺工具应报错，不得跳过并称通过。

```powershell
./verification/scripts/check_verilog.ps1
./verification/scripts/run_tests.ps1 -Suite All -ModelSimBin C:/Library/modelsim/win64
./verification/scripts/run_uart_tests.ps1
./verification/scripts/run_piano_tests.ps1
./verification/scripts/run_display_tests.ps1
./verification/scripts/run_pa_tests.ps1
./verification/scripts/run_latency_tests.ps1 -ExtraTests tb_audio_boundaries,tb_audio_display_isolation
./verification/scripts/check_audio_parameters.ps1
./verification/scripts/check_c_rtl.ps1
& '.venv-studio/Scripts/python.exe' -m unittest discover -s host -p 'test_*.py' -v
./projects/piano/build.ps1
./projects/display/build.ps1
```

可选当前A核心/吉他实现矩阵：`./projects/check_implementation.ps1 -Group All`，共3项。与主钢琴构建分开；模块外壳/显示核心不能当可下载的完整乐器。

此次C成果归并：主工程RTL及主Verilog测试与13键提交保持字节一致；独立C刷新了已发布阶段的4份旧测试接口，并将3份新增测试改为Verilog .v，断言条件未放宽。C17项回归及15个RTL+3个新TB严格编译另行验证，结果见[C输入说明](c-input.md)。旧“57份原测试不变”是13键提交时的结论，不适用于这次有意刷新的独立C测试。

All现在仅覆盖保留的当前实现；退役旧bank、旧板级演示和主目录旧C演示的7项专用测试随实现删除，当前分配器重触发/抢占回归仍保留。已有有效TB检查阈值没有放宽。C独立工程RTL单独编译，原SystemVerilog TB和脚本未修改、未纳入主验证。

## 清理后的执行记录

2026-10-13实际执行：清理前101文件严格Verilog编译通过；清理后84文件严格Verilog编译、All27、UART7、钢琴2、显示6、PA4通过。参数3合法通过、12非法以预期非零状态拒绝；上位机32单测通过。C的56个文件哈希保持不变，其中15个RTL单独严格编译，C原TB未运行。

当前lead=2的14项数字延迟用例、音频边界、显示隔离以及默认ModelSim入口自检也通过；该组最大左声道数字观测延迟为2.063030ms，不代表整机实测。显示核心重新综合通过，但尚未完成屏幕引脚、PLL和外部时序验证。五项Python参考模型与本轮RTL输出对照通过。以上新日志统一保存在`build/cleanup`及`build/regression`。

主钢琴重新完成综合/布局布线，受控/实际process配置一致，仍为5927逻辑、2710寄存器、4 BSRAM、8 DSP，现有约束setup/hold +5.891/+0.127ns。引脚和时序约束只是从旧UART工程移入boards，字节不变；主发声链路无逻辑修改。该次记录在`build/cleanup/piano-build`，不会复制出另一套源码。

## 历史结果不是本轮实物验收

清理前钢琴现有约束下5927逻辑（5235 LUT＋692 ALU）、2710寄存器、4 BSRAM、8 DSP，setup/hold +5.891/+0.127ns。尾音功放排空修复已验证；最大数字观测延迟2.083210→2.063030ms，改善20.18µs。

数字延迟起点是最后稳定按键沿，终点是与新事件有关的完整左声道数字字、阈值1LSB。2.167220ms仅为新空闲C4/固定力度/空队列等指定条件上界，不是任意积压或全部工况的整机保证。真实接点抖动、DAC、功放、音箱和显示实物负载仍待测。

PR1014及DIN/WS相对BCK的完整DAC外部时序仍待闭合；6条已有约束激活不等于全部板级签核。清理不等于烧录成功，不改变四声部为16声部。

## 历史与恢复

查旧版使用Git，不再新建backup/legacy目录：例如`git show f513622:rtl/synth/adsr_voice_bank.v`只读显示旧文件。最新原始指南/用户上传资料仍在`docs/sources`，字体来源和OFL许可仍保留。C完整独立工程按用户选择保留，历史C报告属于队友原记录，不称为本轮重跑。

旧编译缓存的永久删除被工具环境拒绝，已移出仓库到系统临时回收目录；确切位置保存在本机`build/cleanup/cache-location.txt`。这些是旧生成物，不再作为活动工程或新验证证据。
