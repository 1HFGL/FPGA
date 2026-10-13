# 迁移后仿真证据索引（2026-10-13）

本目录只归档实际完成的仿真、负例与入口检查。原始文件来自 `build/b-review-20261013/post-migration/`，保持相对目录和字节内容；[复制清单及 SHA256](copied-evidence-sha256.csv)可核对完整性。没有复制工作库、WLF、音频、帧 HEX、大型逐样本 trace、临时 RTL 副本或第一轮 strict/All 候选日志。综合、布局布线、上板证据不在本索引内。

工具为 Windows ModelSim SE-64 10.6e，编译统一使用 `-vlog01compat -pedanticerrors`，没有启用 SystemVerilog。机器可读汇总见 [simulation-checks.csv](simulation-checks.csv)。

## 实际 17 组检查

| # | 检查 | 实际结果 | 原始证据 |
|---|---|---|---|
| 1 | 最终主工程严格编译 | 101 个 `.v` 文件通过 | [编译日志](strict-final/strict_compile.log)、[输入 SHA](strict-final/strict_inputs.txt) |
| 2 | 上游快照 RTL 严格编译 | 24 文件通过；未运行上游 TB | [日志](upstream-rtl/compile.log)、[输入 SHA](upstream-rtl/inputs.txt) |
| 3 | 最终 All 回归 | 34 个测试平台通过 | [总日志](all-final-console.log)、[34 份日志目录](all-final/logs/)、[输入 SHA](all-final/logs/All_sha256.txt) |
| 4 | UART 回归 | 7 个测试通过 | [总日志](uart-console.log)、[输入 SHA](uart/normal_inputs.txt) |
| 5 | 钢琴回归 | 音色、实际 115200 波特率板级仿真共 2 项通过 | [总日志](piano-console.log)、[输入 SHA](piano/normal_sim_inputs.txt) |
| 6 | 显示回归 | 6 项通过 | [总日志](display-console.log)、[输入 SHA](display/normal_inputs.txt) |
| 7 | 功放尾音排空 | lead=0/2 × 短尾/默认尾音，共 4 项通过 | [总日志](pa-drain-console.log)、[输入 SHA](pa-drain/inputs.txt) |
| 8 | 默认参数钢琴延迟 | 旧、新模式各 14 工况通过 | [结果与上界](latency/latency_summary.json)、[旧 CSV](latency/latency_lead0_normal.csv)、[新 CSV](latency/latency_lead2_normal.csv)、[输入 SHA](latency/normal_inputs.txt) |
| 9 | 音频边界与显示隔离 | 2 项通过 | [缓存边界](latency/tb_audio_boundaries.log)、[显示隔离](latency/tb_audio_display_isolation.log) |
| 10 | 合法音频参数 | case 0、1、14 均通过，退出码 0 | [15 项明细](parameters/summary.csv)、[总日志](parameters-console.log) |
| 11 | 非法音频参数 | case 2～13 均命中预期拒绝，退出码 1 | [15 项明细](parameters/summary.csv)、[参数目录](parameters/) |
| 12 | 默认 ModelSim 入口 | compile、CLI run 均通过 `synth_top_tb` | [编译](default-compile-console.log)、[运行](default-run-console.log)、[输入 SHA](default-run/inputs.txt) |
| 13 | 默认入口错误输入 | 缺工具、缺源码、错误成功标记均拒绝，退出码 1 | [缺工具](missingtool.log)、[缺源码](missing-source.log)、[错误标记](default-negative-marker-console.log) |
| 14 | 空格路径与不同 cwd | 五文件副本从仓库外启动，默认自检通过 | [总日志](space-path-console.log)、[副本输入 SHA](space%20path%20fixture/build/regression/default-modelsim/inputs.txt) |
| 15 | 延迟测试串行变异负例 | 检查器报 `serial word does not match frame-consumed sample`，入口退出码 1 | [失败原始日志](latency-negative/tb_piano_latency_lead0_negative.log)、[入口日志](latency-negative-console.log)、[输入 SHA](latency-negative/negative_inputs.txt) |
| 16 | 活动 C 的 DO 编译入口 | `compile_all.do` 严格编译通过；不运行上游 TB | [控制台日志](compile-all-do-console.log) |
| 17 | A 的教学 DO 入口 | `run_phase_acc.do` 的 15 个相位检查通过 | [控制台日志](a-do-console.log) |

第 11、13、15 项的成功含义是“错误被明确拒绝”，不是错误设计通过测试。ModelSim 的 `$finish` 可能返回 0，因此入口同时检查失败文本和预期成功标记；延迟变异日志正好验证了这种情况。参数总入口仅在逐个确认合法项返回 0、非法项按原因返回非零后才报告 PASS。

## 输入版本与结论边界

最终 strict/All 已包含四个演示顶层显式空接 `.frame_start()` 的兼容修正。其余专项回归先于这次纯连接说明修正；[最终输入比较](latency-input-final-comparison.csv)记录只有 `instrument_adsr_top.v`、`instrument_demo_top.v`、`instrument_presets_top.v`、`single_tone_demo_top.v` 四项哈希不同，它们不在主钢琴测试的活动层次内；主钢琴链路、TB 和延迟脚本哈希不变。未将专项回归伪称为修改后的全部源码重跑。

数字通路采用实际 100000 拍消抖及原 ADSR 96/57600/0/8640。14 个有向工况测得最大值：旧模式 **2.083210 ms**，提前请求模式 **2.063030 ms**。新模式的 3125 系统时钟相位枚举，加“新 C4、力度 100、任意初相位、未饱和且不变背景”至多 7 样本内容边界，得到条件上界 **2.167220 ms**；不是任意抢占／取消流的全局证明，也不包含真实 DAC、功放、机械不稳定或未来 13 键集成。不能据此宣布实物整机延迟已经达标。

旧 B 测试平台未连接新增观察输出时，ModelSim 会报缺少 `frame_start` 连接的兼容警告；保留原日志，不把它删成“零警告”。`compile_all.do` 的 Tcl `puts` 成功标记位于控制台日志，不在 ModelSim transcript；A 的教学 DO 在 batch 下会提示不支持波形缩放，但相位自检实际通过。

## 复现命令

在仓库根目录用 PowerShell 执行。请先把 `$simBin` 换成本机实际工具目录；没有工具应明确失败，不应跳过自检。输出继续写入 `build/`，不会覆盖本报告的归档副本；前三个 strict/upstream/All 入口仍使用各自默认 `build/regression/`，其余通过 `$out` 隔离。原始 CSV 内保留的绝对 `build/...` 路径是当时的记录，跨机器查阅请使用本索引的相对链接。以下脚本相对目录是 [verification/scripts](../../../../../verification/scripts/)。

```powershell
$simBin = 'C:/Library/modelsim/win64'
$scripts = './verification/scripts'
$out = 'build/b-review-20261013/reproduce-verification'
& "$scripts/check_verilog.ps1" -ModelSimBin $simBin
& "$scripts/check_c_rtl.ps1" -ModelSimBin $simBin
& "$scripts/run_tests.ps1" -Suite All -ModelSimBin $simBin
& "$scripts/run_uart_tests.ps1" -ModelSimBin $simBin -OutputDirectory "$out/uart"
& "$scripts/run_piano_tests.ps1" -ModelSimBin $simBin -OutputDirectory "$out/piano"
& "$scripts/run_display_tests.ps1" -ModelSimBin $simBin -OutputDirectory "$out/display"
& "$scripts/run_pa_tests.ps1" -ModelSimBin $simBin -OutputDirectory "$out/pa-drain"
& "$scripts/run_latency_tests.ps1" -ModelSimBin $simBin -OutputDirectory "$out/latency" -LeadModes 0,2 -ExtraTests tb_audio_boundaries,tb_audio_display_isolation
& "$scripts/check_audio_parameters.ps1" -ModelSimBin $simBin -OutputDirectory "$out/parameters"
& "$scripts/run_modelsim.ps1" -ModelSimBin $simBin -Mode compile -OutputDirectory "$out/default-compile"
& "$scripts/run_modelsim.ps1" -ModelSimBin $simBin -Mode run -OutputDirectory "$out/default-run"
```

负例用独立 PowerShell 进程运行，便于直接观察 `$LASTEXITCODE`；以下各次均预期 **1**。参数例子只展示 case 2，正常总入口已自动验证全部 15 项。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scripts/check_audio_parameters.ps1" -ModelSimBin $simBin -OutputDirectory "$out/parameter-single" -Case 2
$LASTEXITCODE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scripts/run_latency_tests.ps1" -ModelSimBin $simBin -OutputDirectory "$out/latency-negative" -LeadModes 0 -NegativeControl
$LASTEXITCODE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scripts/run_modelsim.ps1" -ModelSimBin 'D:/missing-modelsim-bin'
$LASTEXITCODE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scripts/run_modelsim.ps1" -ModelSimBin $simBin -Sources 'rtl/audio/definitely_missing.v'
$LASTEXITCODE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scripts/run_modelsim.ps1" -ModelSimBin $simBin -ExpectedPass NOT_THE_REAL_PASS_MARKER -OutputDirectory "$out/default-negative-marker"
$LASTEXITCODE
```

DO 入口以 `source` 定位自身路径。`compile_all.do` 的 PASS 和 `run_phase_acc.do` 的 `PASS: all 15 checks passed.` 都必须实际出现。

```powershell
$repoPath = (Get-Location).Path.Replace('\','/')
& "$simBin/vsim.exe" -c -do "source {$repoPath/verification/scripts/compile_all.do}; quit -code 0 -f"
& "$simBin/vsim.exe" -c -do "source {$repoPath/verification/scripts/run_phase_acc.do}; quit -code 0 -f"
```

空格路径检查只复制默认入口和其四个源码，不复制工作库；这是入口定位测试，不是另建完整工程。下面使用唯一临时目录，不修改已有文件。

```powershell
$fixture = Join-Path (Get-Location) ("build/space path fixture " + [guid]::NewGuid().ToString('N'))
$files = @('verification/scripts/run_modelsim.ps1', 'verification/tb/audio/synth_top_tb.v',
           'rtl/audio/sample_tick.v', 'rtl/audio/i2s_tx.v', 'rtl/audio/synth_top.v')
foreach ($file in $files) {
    $target = Join-Path $fixture $file
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $file -Destination $target
}
Push-Location (Split-Path -Parent $repoPath)
try {
    & "$fixture/verification/scripts/run_modelsim.ps1" -ModelSimBin $simBin
} finally { Pop-Location }
```
