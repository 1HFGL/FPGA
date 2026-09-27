$ErrorActionPreference = 'Stop'

# 在项目根目录运行，避免 ModelSim 把 Windows 反斜杠当作 Tcl 转义符。
$projectRoot = Split-Path -Parent $PSScriptRoot
$modelSimBin = 'C:\Library\modelsim\win64'
$vlib = Join-Path $modelSimBin 'vlib.exe'
$vlog = Join-Path $modelSimBin 'vlog.exe'
$vsim = Join-Path $modelSimBin 'vsim.exe'
$workLib = 'results/audio_work'

foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (!(Test-Path -LiteralPath $tool)) {
        throw "找不到 ModelSim 工具：$tool"
    }
}

Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Path 'results' -Force | Out-Null
    if (!(Test-Path -LiteralPath 'results/audio_work/_info')) {
        & $vlib $workLib
        if ($LASTEXITCODE -ne 0) { throw '创建仿真库失败' }
    }

    # RTL 按普通 Verilog 编译；测试平台使用 SystemVerilog 的 $fatal。
    & $vlog -nologo -work $workLib 'rtl/sample_tick.v' 'rtl/i2s_tx.v' 'rtl/synth_top.v'
    if ($LASTEXITCODE -ne 0) { throw 'RTL 编译失败' }
    & $vlog -nologo -sv -work $workLib 'sim/sample_tick_tb.v' 'sim/synth_top_tb.v'
    if ($LASTEXITCODE -ne 0) { throw '测试平台编译失败' }

    # 顺序运行，避免两个 vsim 进程同时改写同一仿真库的优化缓存。
    foreach ($top in @('sample_tick_tb', 'synth_top_tb')) {
        $logPath = "results/$top.log"
        & $vsim -c -lib $workLib -l $logPath $top -do 'run -all; quit -f'
        $simExit = $LASTEXITCODE
        $logText = Get-Content -Raw -LiteralPath $logPath
        # 该版 ModelSim 遇到 $fatal 时仍可能返回 0，因此还要检查日志。
        if ($simExit -ne 0 -or
            $logText -match '(?m)^# \*\* (Fatal|Error):' -or
            $logText -notmatch "PASS $top") {
            throw "$top 仿真失败，详见 $logPath"
        }
    }
}
finally {
    Pop-Location
}
