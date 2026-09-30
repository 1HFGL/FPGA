# 高云 EDA A+B+C demo 工程

保持整个仓库的相对目录结构，在 EDA 的 File → Open Project 打开本目录 `fpga_project.gprj`。

- 器件：GW5AT-60B / GW5AT-LV60PG484AC1/I0 / Device Version B。
- 默认顶层：`instrument_demo_top`，S2 与 S1 弹奏 C4/E4，S4 复位。
- 自动四声部版：`instrument_demo_auto_top`，复位后播放一次约 1 秒。
- 板卡：用户确认 NEO Dock 31004；V22 名义 50MHz，按键 BANK9 为 1.5V，音频为 3.3V。
- 约束：`../boards/tang_mega_60k_31004/demo.cst` 与 `demo.sdc`。
- ROM Include Path 为 `..`，保留 `rtl/rom/sine_1024.mem`。

已检测并实际运行本机 Gowin 1.9.12.04；从仓库根目录执行：

```powershell
Push-Location .\fpga_project
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_demo.tcl
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_auto_demo.tcl
Pop-Location
```

其他电脑把可执行文件路径换成自己的安装位置。脚本只构建，不连接板卡、不刷 Flash。默认 GUI 配置仍保留普通按键顶层；如在 GUI 手动改为自动顶层，同时把输出名改成 `instrument_demo_auto`。

输出分别为 `impl/pnr/instrument_demo.fs`、`instrument_demo_auto.fs`。大体积下载文件、工作库和工具缓存不提交；上传源码、约束、测试和构建报告。**旧的 `fpga_project.fs` 自动分配了引脚，不要继续下载它。**

原单音顶层和通用 25MHz 的 `audio_clk.sdc` 仅保留为仿真/历史参考，不再是本工程的活动顶层或时钟约束。完整接口、验证和上板步骤见 [demo 说明](../docs/abc-demo.md)。
