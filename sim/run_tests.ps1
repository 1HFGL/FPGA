[CmdletBinding()]
param(
    [ValidateSet('A','B','All')][string]$Suite = 'A',
    [string]$ModelSimBin = $env:MODELSIM_BIN
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $ModelSimBin) {
    $found = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if ($found) { $ModelSimBin = Split-Path -Parent $found.Source }
}
if (-not $ModelSimBin) { throw 'Specify -ModelSimBin or set MODELSIM_BIN (the folder containing vsim.exe).' }
foreach ($name in @('vlib','vlog','vsim')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSimBin ($name+'.exe')))) { throw "Missing ModelSim tool: $name" }
}
$tests = @()
$sources = @()
$markers = @{
    tb_phase_acc = 'PASS: all 15 checks passed.'
    tb_wave_lut = 'PASS: all 1035 checks passed; all 1024 ROM addresses verified.'
    tb_voice_dds = 'PASS: voice_dds; 4810 valid samples matched; 1200025 clock checks passed.'
    sample_tick_tb = 'PASS sample_tick_tb'
    synth_top_tb = 'PASS synth_top_tb'
}
if ($Suite -in @('A','All')) {
    $tests += @('tb_phase_acc','tb_wave_lut','tb_voice_dds')
    $sources += @('rtl/phase_acc.v','rtl/wave_lut.v','rtl/voice_dds.v','sim/tb_phase_acc.v','sim/tb_wave_lut.v','sim/tb_voice_dds.v')
}
if ($Suite -in @('B','All')) {
    $tests += @('sample_tick_tb','synth_top_tb')
    $sources += @('rtl/sample_tick.v','rtl/i2s_tx.v','rtl/synth_top.v','sim/sample_tick_tb.v','sim/synth_top_tb.v')
}
Push-Location $root
try {
    New-Item -ItemType Directory -Path 'results/logs','results/waves' -Force | Out-Null
    $lib = 'results/regression_work'
    if (-not (Test-Path -LiteralPath "$lib/_info")) {
        & (Join-Path $ModelSimBin 'vlib.exe') $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed.' }
    }
    & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $lib @sources
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
    foreach ($top in $tests) {
        $macro = "results/logs/${top}_run.do"
        @"
onerror {quit -code 1 -f}
onbreak {resume}
run -all
quit -code 0 -f
"@ | Set-Content -LiteralPath $macro -Encoding ascii
        $log = "results/logs/$top.log"
        $extraArgs = @()
        if ($top -eq 'tb_voice_dds') { $extraArgs = @('+DDS_TRACE=results/logs/dds_trace.txt') }
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib -l $log -wlf "results/waves/$top.wlf" $top @extraArgs -do "do {$macro}"
        $exitCode = $LASTEXITCODE
        $logText = Get-Content -LiteralPath $log -Raw
        if ($exitCode -ne 0 -or $logText -match '(?m)^# \*\* (Fatal|Error):' -or -not $logText.Contains($markers[$top])) {
            throw "$top failed or did not finish all checks; see $log"
        }
        Write-Output "VERIFIED $top"
    }
    Write-Output "PASS: suite $Suite ($($tests.Count) testbenches)."
} finally { Pop-Location }
