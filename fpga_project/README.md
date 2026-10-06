# 高云 EDA A+B+C demo 工程

保持整个仓库的相对目录结构，在 EDA 的 File → Open Project 打开本目录 `fpga_project.gprj`。

2026-10-06审查后：普通／自动顶层已接入A最新 `voice_bank_adsr` 和 `sample_mixer4`，C分配器四项问题已修复并压缩排名资源，原bank／旧demo保留。26项仿真、五个参考程序和负向检查通过；两版下载文件已重新生成。50MHz下最差Setup/Hold普通+6.619/+0.125ns、自动+5.669/+0.123ns，违例0/0，8/8端口约束。普通版LUT/寄存器为2119/965。PR1014及完整外部DAC时序仍待验证，新版未下载。当前配置保留普通顶层。见 [审查报告](../docs/code-review-20261006.md) 与 [接入说明](../docs/poly-integration.md)。

- 器件：GW5AT-60B / GW5AT-LV60PG484AC1/I0 / Device Version B。
- 新普通ADSR顶层：`instrument_adsr_top`，KEY1／KEY2弹奏C4／E4，KEY0复位；输出名 `instrument_adsr`。
- 新自动ADSR顶层：`instrument_adsr_auto_top`，约1秒后进入120ms释放；输出名 `instrument_adsr_auto`。
- 旧渐变顶层 `instrument_demo_top`／`instrument_demo_auto_top` 保留作回退，不与新ADSR下载文件混用。
- 板卡：用户确认 NEO Dock 31004；V22 名义 50MHz，按键 BANK9 为 1.5V，音频为 3.3V。
- 约束：`../boards/tang_mega_60k_31004/demo.cst` 与 `demo.sdc`。
- ROM Include Path 为 `..`，保留 `rtl/rom/sine_1024.mem`。

已检测并实际运行本机 Gowin 1.9.12.04；从仓库根目录执行：

```powershell
Push-Location .\fpga_project
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_demo.tcl
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_auto_demo.tcl
Pop-Location
```

其他电脑把可执行文件路径换成自己的安装位置。脚本只构建，不连接板卡、不刷Flash。两个脚本共享工程配置，不要并行运行；最后运行哪版，就核对GUI顶层与输出名是哪版。交付时配置为新普通ADSR版。本机GUI若缓存旧设置，请重新打开工程并检查。

新输出为 `impl/pnr/instrument_adsr.fs`、`instrument_adsr_auto.fs`。回退时用原 `build_demo.tcl`／`build_auto_demo.tcl` 生成 `instrument_demo.fs`／`instrument_demo_auto.fs`。大体积下载文件、工作库和工具缓存不提交。**旧的 `fpga_project.fs` 自动分配了引脚，不要继续下载它。**

2026-10-02新ADSR普通／自动版已实际综合、布局布线和生成下载文件，50MHz下Setup／Hold违例为0，8个端口已约束。时序裕量很小，PR1014及完整外部DAC时序仍待验证，尚未下载新版本。见 [ADSR集成说明](../docs/adsr-integration.md)。

原单音顶层和通用 25MHz 的 `audio_clk.sdc` 仅保留为仿真/历史参考，不再是本工程的活动顶层或时钟约束。完整接口、验证和上板步骤见 [demo 说明](../docs/abc-demo.md)。
