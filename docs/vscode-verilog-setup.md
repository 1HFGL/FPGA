# VS Code与ModelSim：当前工程入口

2026-10-13目录重整后，默认仿真改为实际存在的B音频测试`synth_top_tb`，不再引用已不存在的DDS/计数器练习。主工程只使用Verilog-2001，编译选项固定`-vlog01compat -pedanticerrors`，不用`-sv`绕过语法问题。

在仓库根的PowerShell运行：

```powershell
./verification/scripts/run_modelsim.ps1 -Mode compile
./verification/scripts/run_modelsim.ps1 -Mode run
./verification/scripts/check_verilog.ps1
```

默认脚本使用本机`C:/Library/modelsim/win64`，也可按脚本参数指定其他位置。缺少工具应明确报错而不是跳过。默认`run`是有自检的命令行仿真；需要看波形时显式运行 `./verification/scripts/run_modelsim.ps1 -Gui`。日志和工作库在`build/`，不放回源码目录；GUI会话不等于自动自检通过。

VS Code菜单“终端→运行任务”中的编译/运行任务指向同一脚本；插件自己的单文件检查不能替代项目全量编译和自检。`.vscode/config.json`顶层导航已指向`rtl/top/instrument_uart_piano_top.v`，若换到其他机器需在插件里重新选择实际路径。

预期现象：编译没有错误，运行日志出现`PASS synth_top_tb`。测试验证帧格式、缓存、缺样本和复位，不是实物音频验收。完整回归与工程入口见[目录说明](repository-layout.md)。

不要混编`upstream`快照和主工程中的同名模块，不要改队友tb来适配主工程。原工作库和旧日志已保留在`build/retained-before-migration/`；历史验证结果按原版本理解，不能当作本次运行结果。
