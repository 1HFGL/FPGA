# VS Code + Verilog + ModelSim 配置说明

本文档针对当前项目的 Windows 环境，目标是让成员能够在 VS Code 中编辑、格式化、检查并启动 ModelSim 仿真。

## 1. 当前工具与职责

| 工具 | 实际位置或版本 | 作用 |
| --- | --- | --- |
| VS Code | `D:\Microsoft VS Code\bin\code.cmd` | 编辑器、任务入口 |
| ModelSim | `C:\Library\modelsim\win64` | Verilog 编译、仿真、波形 |
| ModelSim 版本 | SE-64 10.6e | 当前已检测到的版本 |
| Verilog Hdl Format | 4.8.20260712 | HDL 导航、例化和 ModelSim 语法检查 |
| Verilog-HDL/SystemVerilog | 1.29.0 | Verilog 语言支持 |
| SystemVerilog and Verilog Formatter | 3.4.1 | Verible 格式化器，负责紧凑排版 |

编辑器插件不等于仿真器：插件负责调用工具，真正的 Verilog 编译和仿真仍由 ModelSim 完成。

## 2. 工作区文件

当前工作区使用以下配置：

- `.vscode/settings.json`：格式化器、语言检查和编辑器设置。
- `.vscode/tasks.json`：VS Code 中的编译和仿真任务。
- `run_modelsim.ps1`：可重复执行的 ModelSim 编译/启动脚本。
- `.vscode/config.json`：Verilog Hdl Format 的文件树顶层配置，当前指向 `rtl/bcd_counter.v`。

不要把 `.vscode/config.json` 当作 VS Code 的普通设置文件；普通设置写入 `.vscode/settings.json`。

## 3. 格式化规则

当前采用紧凑易读风格：

- 4 个空格缩进，不使用 Tab。
- 目标行宽 100 列。
- 端口声明、变量声明、命名端口连接和赋值使用左对齐，不人为保留很宽的空列。
- `else` 与前面的 `end` 保持同一行：`end else begin`。
- 保存 Verilog 文件时不自动改写，保留手动输入的控制结构排版。

当前截图中的排版要求把简单分支写成多行，但不使用 `begin/end`。Verible 会把这种“条件 + 单条赋值”合并到同一行，因此不能用它自动生成完全相同的样式。工作区已关闭保存时自动格式化，以免保存时改变这种排版。

需要使用标准 Verible 排版时，打开 `.v` 或 `.sv` 文件后按 `Shift+Alt+F`，但它会采用 Verible 的规范布局。也可以打开命令面板，执行：

```text
SystemVerilog Formatter - Format this file
```

只格式化选中区域时执行：

```text
SystemVerilog Formatter - Format selection
```

旧的 Verilog Hdl Format 插件仍保留 `Ctrl+L`、`Ctrl+U`、`Ctrl+K` 等专用命令，但它们不是 VS Code 标准格式化接口，当前不作为主要格式化入口。

## 4. ModelSim 语法检查

工作区已经选择 ModelSim 作为 Verilog Hdl Format 的 linter：

```json
{
    "FPGA_verilog.linting.path": "C:/Library/modelsim/win64/",
    "FPGA_verilog.linting.linter": "modelsim",
    "FPGA_verilog.linting.modelsim.work": "work"
}
```

路径末尾必须有 `/`，因为插件会在这个路径后拼接 `vlog`。

脚本会在 `sim/` 中维护名为 `work` 的 ModelSim 工作库。若需要手动创建，VS Code 终端执行：

```powershell
cd D:\Project\fpga_contest
cd .\sim
& "C:\Library\modelsim\win64\vlib.exe" work
```

打开 Verilog 文件并保存后，插件会对当前文件运行检查。也可以从命令面板执行：

```text
Verilog: Rerun lint tool
```

这里的检查是单文件语法检查。测试平台引用其他模块时，先使用项目任务完整编译所有源文件，不要把一条红线直接等同于完整仿真失败。
单文件检查可能在项目根目录自动生成 `work/` 缓存；它不是源码。完整脚本使用的是 `sim/work/`，两者都不要手工编辑。

## 5. 启动完整仿真

当前脚本的默认仿真是 DDS，明确输入是：

- RTL：`rtl/dds.v`
- 测试平台：`sim/dds_tb.v`
- 仿真顶层：`dds_tb`

在 VS Code 中按 `Ctrl+Shift+P`，选择 `Tasks: Run Task`，然后选择：

```text
ModelSim: 编译默认仿真
```

或：

```text
ModelSim: 打开默认仿真
```

第二个任务会先编译，编译成功后启动 ModelSim GUI，自动加入：

```text
sim:/dds_tb/*
```

波形文件保存到 `results/waves/dds_tb.wlf`。当前测试平台使用 `$finish`，仿真结束后会停止，便于查看 DDS 波形。

也可以直接在 VS Code 终端执行：

```powershell
.\run_modelsim.ps1 -Mode compile
.\run_modelsim.ps1 -Mode run
```

VS Code 任务只传入 `-Mode`，不会覆盖脚本的 `$Top` 和 `$Sources`；因此当前任务与直接调用脚本一样，默认入口都是 DDS（`dds_tb`）。`-Sources` 可以使用逗号或分号分隔多个源文件。临时测试计数器或 PWM 时可在终端显式指定源文件：

```powershell
.\run_modelsim.ps1 -Mode run -Top pwm_tb -Sources rtl/pwm.v,sim/pwm_tb.v
```

临时运行计数器可执行：

```powershell
.\run_modelsim.ps1 -Mode run -Top counter_tb -Sources rtl/counter.v,sim/counter_tb.v
```

在 VS Code 任务中必须把多个源文件作为同一个参数传递；不要把它们拆成两个独立参数，否则旧版 PowerShell 可能把第二个路径误绑定为工作库名称。

## 6. 更换为其他 Verilog 工程

修改 `run_modelsim.ps1` 开头的三个值：

```powershell
$Top = 'new_counter_tb'
$Sources = @('rtl/new_counter.v', 'sim/new_counter_tb.v')
$WorkLibrary = 'work'
```

不要使用 `*.v` 自动编译整个目录，否则旧测试平台或未完成草稿可能被错误加入工程。

更换工程后，确认测试平台中存在：

```verilog
module new_counter_tb;
```

`$Top` 必须填写测试平台的 `module` 名称，不是文件名。

## 7. 常见问题

### 找不到 `counter_tb`

先在 `sim/` 目录或 ModelSim 已加载项目工作库的前提下确认已经加载正确顶层：

```tcl
vsim work.counter_tb
```

波形路径中的下划线直接写 `_`，不要写成 `\_`。

### `vlog` 找不到 work 库

在 `sim/` 目录创建一次：

```powershell
cd D:\Project\fpga_contest\sim
& "C:\Library\modelsim\win64\vlib.exe" work
```

脚本在运行时也会自动检查并创建该库。

### 代码格式化没有反应

确认当前文件语言模式是 `Verilog` 或 `SystemVerilog`，然后执行 `Developer: Reload Window`。检查右下角默认格式化器是否为 `SystemVerilog and Verilog Formatter`。

### ModelSim 编译成功但 LED 没变化

当前 RTL 每 25,000,000 个 50 MHz 时钟周期翻转一次 LED，大约每 0.5 秒翻转一次；测试平台还要先保持复位 200 个时钟周期。先观察 `rst`、`cout` 和 `led`，不要只看 LED。

### 编译成功是否代表项目完成

不代表。当前只能证明代码已被 ModelSim 接受并可启动仿真。综合、布局布线、时序、上板、I2S 输出和真实延迟仍需分别验证。

## 8. 当前验证状态

- 工具可用：ModelSim SE-64 10.6e 已检测。
- 源码编译：`rtl/counter.v` 与 `sim/counter_tb.v` 已用 ModelSim 编译通过，0 errors、0 warnings。
- 格式化：采用 Verible 4 空格配置，需在 VS Code 重载后验证界面入口。
- 仿真行为：需观察新任务启动后的 `rst`、`cout`、`led` 波形；尚未宣称上板或音频验证通过。
