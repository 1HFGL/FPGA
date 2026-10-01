[CmdletBinding()]
param(
    [ValidateSet('A','ADSR','B','C','AB','Demo','All')][string]$Suite = 'A',
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [switch]$NegativeControl
)
$ErrorActionPreference = 'Stop'
if ($NegativeControl -and $Suite -ne 'AB') {
    throw 'NegativeControl is only supported with -Suite AB.'
}
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
    tb_adsr_env = 'PASS: adsr_env duration checks'
    tb_sample_gain = 'PASS: sample_gain exhaustive checks'
    tb_voice_adsr = 'PASS: voice_adsr sample and pipeline checks'
    sample_tick_tb = 'PASS sample_tick_tb'
    synth_top_tb = 'PASS synth_top_tb'
    tb_single_tone_ab = 'PASS tb_single_tone_ab:'
    tb_input_sync_debounce = 'PASS: tb_input_sync_debounce'
    tb_pressure_if = 'PASS: tb_pressure_if'
    tb_event_encoder = 'PASS: tb_event_encoder'
    tb_voice_allocator = 'PASS: tb_voice_allocator_32'
    tb_interaction_top = 'PASS: tb_interaction_top_32key'
    tb_voice_test_pattern = 'PASS: tb_voice_test_pattern'
    tb_demo_voice_bank = 'PASS tb_demo_voice_bank'
    tb_instrument_demo = 'PASS tb_instrument_demo'
}
if ($Suite -in @('A','AB','Demo','All')) {
    $tests += @('tb_phase_acc','tb_wave_lut','tb_voice_dds')
    $sources += @('rtl/phase_acc.v','rtl/wave_lut.v','rtl/voice_dds.v','sim/tb_phase_acc.v','sim/tb_wave_lut.v','sim/tb_voice_dds.v')
}
if ($Suite -in @('ADSR','All')) {
    $tests += @('tb_adsr_env','tb_sample_gain','tb_voice_adsr')
    $sources += @('rtl/adsr_env.v','rtl/sample_gain.v','rtl/voice_adsr.v','sim/tb_adsr_env.v','sim/tb_sample_gain.v','sim/tb_voice_adsr.v')
}
if ($Suite -in @('B','AB','Demo','All')) {
    $tests += @('sample_tick_tb','synth_top_tb')
    $sources += @('rtl/sample_tick.v','rtl/i2s_tx.v','rtl/synth_top.v','sim/sample_tick_tb.v','sim/synth_top_tb.v')
}
if ($Suite -in @('AB','All')) {
    $tests += 'tb_single_tone_ab'
    $sources += @('rtl/single_tone_demo_top.v','sim/tb_single_tone_ab.v')
}
if ($Suite -in @('C','Demo','All')) {
    $cModules = @('input_sync_debounce','touch_or_key_if','pressure_if','event_encoder','voice_allocator','reset_sync','voice_test_pattern','interaction_top','board_top','board_test_top')
    $cTests = @('tb_input_sync_debounce','tb_pressure_if','tb_event_encoder','tb_voice_allocator','tb_interaction_top','tb_voice_test_pattern')
    $sources += @($cModules | ForEach-Object { "rtl/$_.v" })
    $sources += @($cTests | ForEach-Object { "tb/$_.sv" })
    $tests += $cTests
}
if ($Suite -in @('Demo','All')) {
    $sources += @('rtl/note_phase_lut.v','rtl/demo_voice_bank.v','rtl/instrument_demo_top.v','sim/tb_demo_voice_bank.sv','sim/tb_instrument_demo.sv')
    $tests += @('tb_demo_voice_bank','tb_instrument_demo')
}
Push-Location $root
try {
    New-Item -ItemType Directory -Path 'results/logs','results/waves' -Force | Out-Null
    # ROM 虽不由 vlog 直接编译，仍是功能输入；记录本次所有源码/波表哈希。
    $manifestInputs = @($sources) + @('sim/run_tests.ps1')
    if ($Suite -in @('A','AB','Demo','All')) { $manifestInputs += 'rtl/rom/sine_1024.mem' }
    $manifestName = if ($NegativeControl) { "${Suite}_negative_sha256.txt" } else { "${Suite}_sha256.txt" }
    $manifestLines = @("suite=$Suite negative_control=$NegativeControl")
    foreach ($source in $manifestInputs) {
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $manifestLines += "$hash  $source"
    }
    $manifestLines | Set-Content -LiteralPath "results/logs/$manifestName" -Encoding ascii
    # 负向验证使用独立工作库，避免污染正常回归的编译产物。
    $lib = if ($NegativeControl) { 'results/regression_negative_work' } else { 'results/regression_work' }
    if (-not (Test-Path -LiteralPath "$lib/_info")) {
        & (Join-Path $ModelSimBin 'vlib.exe') $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed.' }
    }
    $compileArgs = @('-sv')
    if ($NegativeControl) { $compileArgs += '+define+AB_NEGATIVE_CONTROL' }
    & (Join-Path $ModelSimBin 'vlog.exe') @compileArgs -work $lib @sources
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
    foreach ($top in $tests) {
        $macro = "results/logs/${top}_run.do"
        @"
onerror {quit -code 1 -f}
onbreak {quit -code 0 -f}
# 老 A 测试使用 stop；日志必须含 PASS 且不含 FAIL，不能只看退出码。
# 原 DDS 双音高用例需要略多于 100ms；1s 是异常未结束的兜底上限。
run 1 sec
quit -code 0 -f
"@ | Set-Content -LiteralPath $macro -Encoding ascii
        $log = if ($NegativeControl) {
            "results/logs/${top}_negative.log"
        } else {
            "results/logs/$top.log"
        }
        $extraArgs = @()
        if ($top -eq 'tb_voice_dds') { $extraArgs = @('+DDS_TRACE=results/logs/dds_trace.txt') }
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib -l $log -wlf "results/waves/$top.wlf" $top @extraArgs -do "do {$macro}"
        $exitCode = $LASTEXITCODE
        $logText = Get-Content -LiteralPath $log -Raw
        if ($exitCode -ne 0 -or $logText -match '(?m)^# \*\* (Fatal|Error):|(?m)^#\s*FAIL' -or -not $logText.Contains($markers[$top])) {
            throw "$top failed or did not finish all checks; see $log"
        }
        Write-Output "VERIFIED $top"
    }
    Write-Output "PASS: suite $Suite ($($tests.Count) testbenches)."
} finally { Pop-Location }
