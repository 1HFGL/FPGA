# 2026-10-11重新验证记录

本目录是本次实际运行产生的文本证据，不替代实物测试。说明及优化结论见[整机审查](../../project-review-20261011.md)。第三方历史报告保留在各自日期目录。

## 结果

- 严格Verilog-2001：84文件，0错误/警告。`strict_inputs.txt`记录源码哈希和编译参数，`strict_compile.log`记录结果。
- 正常仿真43项：All 34、UART 7、钢琴2；日志和输入清单在`simulation/`。
- 钢琴错误ROM负向对照、UART来源编号破坏对照均正确失败；带`negative`/`source_mutation`的日志不得当正常通过日志。
- `sync-review-python.log`：新双音色/乐器轨迹、两组ROM的独立数学核对。
- `build-piano/`：当前UART钢琴重新综合、布局布线和位流生成证据；5142 LUT、692 ALU、2710寄存器、4 BSRAM、8 DSP，Setup/Hold +6.435/+0.223ns。
- `build-instruments/`：队友独立板键试听工程重新实现及ROM/连接审计；Setup/Hold +5.948/+0.216ns。

保留限制：PR1014仍存在，DAC完整外部时序未签核；未烧录、未试听本次位流、未测整机延迟。生成位流没有加入仓库。每个工程资源不能相互代替。

## 复现

在仓库根目录PowerShell运行；以下路径是本机已核实的工具位置，其他成员需改为自己安装路径。

```powershell
.\sim\check_verilog.ps1
.\sim\run_tests.ps1 -Suite All -ModelSimBin C:/Library/modelsim/win64
.\sim\run_uart_tests.ps1
.\sim\run_piano_tests.ps1
.\fpga_project\uart_piano\build.ps1
& D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe ./fpga_project/instruments_board/run.tcl
$reviewPython='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $reviewPython model/check_instrument_bank.py
& $reviewPython model/check_timbre_bank.py
& $reviewPython model/check_instrument_roms.py
& $reviewPython model/check_timbre_rom.py
& $reviewPython model/check_presets_board.py --report results/sync-review-20261011/instruments-board-audit.json
```

负向对照预期脚本报错并退出非零，不能与正常测试一起要求全为0：

```powershell
.\sim\run_piano_tests.ps1 -NegativeControl
.\sim\run_uart_tests.ps1 -SourceMutation -Tests tb_uart_instrument
```

当前严格门禁扫描Git所管理及未忽略的新RTL/测试/工程辅助文件，排除未纳入项目的厂商Documents模板和生成缓存。定长UART测试文本上限1024字节，覆盖原512/513字节命令边界；没有缩减原有边界断言。
