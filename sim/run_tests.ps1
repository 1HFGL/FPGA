[CmdletBinding()]
param(
    [ValidateSet('A','ADSR','ADSRMath','PolyADSR','Timbre','Instruments','PresetsBoard','B','C','AB','Demo','ADSRDemo','Review','All')][string]$Suite = 'A',
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [switch]$NegativeControl
)
$ErrorActionPreference = 'Stop'
if ($NegativeControl -and $Suite -notin @('AB','ADSRDemo','ADSRMath','PresetsBoard')) {
    throw 'NegativeControl requires AB, ADSRDemo, ADSRMath or PresetsBoard.'
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
    tb_adsr_arithmetic = 'PASS: adsr arithmetic exhaustive checks'
    tb_sample_gain = 'PASS: sample_gain exhaustive checks'
    tb_voice_adsr = 'PASS: voice_adsr sample and pipeline checks'
    tb_sample_mixer4 = 'PASS: sample_mixer4 signed boundaries, saturation, idle and reset.'
    tb_voice_bank_adsr = 'PASS: voice_bank_adsr four independent envelopes, triggers, pipeline and mix.'
    tb_wave_lut_timbre = 'PASS: two timbre ROMs, idle/reset, direct threshold and R1 pipeline.'
    tb_timbre_bank = 'PASS: tb_timbre_bank'
    tb_timbre_preview = 'PASS: two RTL timbre preview segments, 48000 samples each, tails silent.'
    tb_instrument_wave = 'PASS: instrument ROMs, direct threshold and R2 pipeline.'
    tb_instrument_bank = 'PASS: tb_instrument_bank'
    tb_instrument_preview = 'PASS: instrument RTL preview, 432000 samples, four silent tails.'
    tb_instrument_presets = 'PASS: tb_instrument_presets'
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
    tb_adsr_voice_bank = 'PASS tb_adsr_voice_bank'
    tb_instrument_adsr = 'PASS tb_instrument_adsr'
    tb_allocator_trigger = 'PASS tb_allocator_trigger'
    tb_allocator_age = 'PASS tb_allocator_age:'
    tb_allocator_owner = 'PASS tb_allocator_owner:'
    tb_allocator_expression_owner = 'PASS tb_allocator_expression_owner:'
    tb_allocator_expression_reset = 'PASS tb_allocator_expression_reset:'
}
if ($Suite -in @('A','ADSR','AB','Demo','ADSRDemo','All')) {
    if ($Suite -ne 'ADSR') { $tests += @('tb_phase_acc','tb_wave_lut','tb_voice_dds') }
    $sources += @('rtl/phase_acc.v','rtl/wave_lut.v','rtl/voice_dds.v','sim/tb_phase_acc.v','sim/tb_wave_lut.v','sim/tb_voice_dds.v')
}
if ($Suite -in @('A','ADSR','ADSRDemo','All')) {
    $tests += @('tb_adsr_env','tb_sample_gain','tb_voice_adsr')
    # 单独运行 ADSR 时，也必须显式编译 voice_adsr 依赖的 DDS 模块。
    $sources += @('rtl/phase_acc.v','rtl/wave_lut.v','rtl/voice_dds.v',
                  'rtl/adsr_env.v','rtl/sample_gain.v','rtl/voice_adsr.v',
                  'sim/tb_adsr_env.v','sim/tb_sample_gain.v','sim/tb_voice_adsr.v')
}
if ($Suite -in @('A','ADSR','ADSRMath','ADSRDemo','All')) {
    $sources += @('rtl/adsr_env.v','sim/tb_adsr_arithmetic.v')
    $tests += 'tb_adsr_arithmetic'
}
if ($Suite -in @('A','PolyADSR','All')) {
    $tests += @('tb_sample_mixer4','tb_voice_bank_adsr')
    $sources += @('rtl/phase_acc.v','rtl/wave_lut.v','rtl/voice_dds.v',
                  'rtl/adsr_env.v','rtl/sample_gain.v','rtl/voice_adsr.v',
                  'rtl/note_phase_lut.v','rtl/sample_mixer4.v','rtl/voice_bank_adsr.v',
                  'rtl/wave_lut_timbre.v','rtl/voice_timbre_adsr.v',
                  'sim/tb_sample_mixer4.v','sim/tb_voice_bank_adsr.v')
}
if ($Suite -in @('A','Timbre','All')) {
    $tests += @('tb_wave_lut_timbre','tb_timbre_bank','tb_timbre_preview')
    $sources += @('rtl/phase_acc.v','rtl/wave_lut.v','rtl/wave_lut_timbre.v',
                  'rtl/adsr_env.v','rtl/sample_gain.v','rtl/voice_timbre_adsr.v',
                  'rtl/note_phase_lut.v','rtl/sample_mixer4.v','rtl/voice_bank_adsr.v',
                  'sim/tb_wave_lut_timbre.v','sim/tb_timbre_bank.v','sim/tb_timbre_preview.v')
}
if ($Suite -in @('A','Instruments','All')) {
    $tests += @('tb_instrument_wave','tb_instrument_bank','tb_instrument_preview')
    $sources += @('rtl/phase_acc.v','rtl/wave_lut.v','rtl/instrument_wave.v',
                  'rtl/instrument_env.v','rtl/sample_gain.v','rtl/voice_instrument.v',
                  'rtl/note_phase_lut.v','rtl/sample_mixer4.v','rtl/voice_bank_instruments.v',
                  'sim/tb_instrument_wave.v','sim/tb_instrument_bank.v','sim/tb_instrument_preview.v')
}
if ($Suite -in @('PresetsBoard','All')) {
    $tests += 'tb_instrument_presets'
    $sources += @('rtl/instrument_presets_top.v','rtl/input_sync_debounce.v',
                  'rtl/synth_top.v','rtl/sample_tick.v','rtl/i2s_tx.v',
                  'rtl/phase_acc.v','rtl/wave_lut.v','rtl/instrument_wave.v',
                  'rtl/instrument_env.v','rtl/sample_gain.v','rtl/voice_instrument.v',
                  'rtl/note_phase_lut.v','rtl/sample_mixer4.v','rtl/voice_bank_instruments.v',
                  'sim/tb_instrument_presets.v')
}
if ($Suite -in @('B','AB','Demo','ADSRDemo','All')) {
    $tests += @('sample_tick_tb','synth_top_tb')
    $sources += @('rtl/sample_tick.v','rtl/i2s_tx.v','rtl/synth_top.v','sim/sample_tick_tb.v','sim/synth_top_tb.v')
}
if ($Suite -in @('AB','All')) {
    $tests += 'tb_single_tone_ab'
    $sources += @('rtl/single_tone_demo_top.v','sim/tb_single_tone_ab.v')
}
if ($Suite -in @('C','Demo','ADSRDemo','All')) {
    $cModules = @('input_sync_debounce','touch_or_key_if','pressure_if','event_encoder','voice_allocator','reset_sync','voice_test_pattern','interaction_top','board_top','board_test_top')
    $cTests = @('tb_input_sync_debounce','tb_pressure_if','tb_event_encoder','tb_voice_allocator','tb_interaction_top','tb_voice_test_pattern')
    $sources += @($cModules | ForEach-Object { "rtl/$_.v" })
    $sources += @($cTests | ForEach-Object { "tb/$_.v" })
    $tests += $cTests
}
if ($Suite -in @('Demo','All')) {
    $sources += @('rtl/note_phase_lut.v','rtl/demo_voice_bank.v','rtl/instrument_demo_top.v','sim/tb_demo_voice_bank.v','sim/tb_instrument_demo.v')
    $tests += @('tb_demo_voice_bank','tb_instrument_demo')
}
if ($Suite -in @('ADSRDemo','All')) {
    $sources += @('rtl/note_phase_lut.v','rtl/adsr_voice_bank.v','rtl/sample_mixer4.v',
        'rtl/voice_bank_adsr.v','rtl/wave_lut_timbre.v','rtl/voice_timbre_adsr.v','rtl/instrument_adsr_top.v',
        'sim/tb_adsr_voice_bank.v','sim/tb_instrument_adsr.v','sim/tb_allocator_trigger.v')
    $tests += @('tb_adsr_voice_bank','tb_instrument_adsr','tb_allocator_trigger')
}
# 两套四声部测试都保留，共用 DDS 源码只编译一次。
if ($Suite -in @('C','Demo','ADSRDemo','Review','All')) {
    $sources += @('rtl/voice_allocator.v','sim/tb_allocator_review.v')
    $tests += @('tb_allocator_age','tb_allocator_owner','tb_allocator_expression_owner','tb_allocator_expression_reset')
}
$sources = @($sources | Select-Object -Unique)
if ($NegativeControl -and $Suite -eq 'ADSRDemo') { $tests = @('tb_instrument_adsr') }
Push-Location $root
try {
    New-Item -ItemType Directory -Path 'results/logs','results/waves' -Force | Out-Null
    # ROM 虽不由 vlog 直接编译，仍是功能输入；记录本次所有源码/波表哈希。
    $manifestInputs = @($sources) + @('sim/run_tests.ps1')
    if ($Suite -in @('A','ADSR','PolyADSR','Timbre','Instruments','PresetsBoard','AB','Demo','ADSRDemo','All')) { $manifestInputs += 'rtl/rom/sine_1024.mem' }
    if ($Suite -in @('A','PolyADSR','Timbre','ADSRDemo','All')) { $manifestInputs += 'rtl/rom/bright_1024.mem' }
    if ($Suite -in @('A','Instruments','PresetsBoard','All')) { $manifestInputs += @('rtl/rom/guitar_1024.mem','rtl/rom/strings_1024.mem') }
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
    $compileArgs = @('-vlog01compat','-pedanticerrors')
    if ($NegativeControl) {
        $compileArgs += $(if ($Suite -eq 'AB') { '+define+AB_NEGATIVE_CONTROL' }
            elseif ($Suite -eq 'ADSRMath') { '+define+ADSR_ARITH_NEGATIVE_CONTROL' }
            elseif ($Suite -eq 'PresetsBoard') { '+define+PRESETS_BOARD_NEGATIVE_CONTROL' }
            else { '+define+ADSR_NEGATIVE_CONTROL' })
    }
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
        if ($top -eq 'tb_voice_adsr') { $extraArgs = @('+ADSR_TRACE=results/logs/adsr_trace.txt') }
        if ($top -eq 'tb_voice_bank_adsr') {
            $extraArgs = @('+POLY_TRACE_DEFAULT=results/logs/poly_adsr_default_trace.txt',
                           '+POLY_TRACE_BOUNDARY=results/logs/poly_adsr_boundary_trace.txt')
        }
        if ($top -eq 'tb_timbre_bank') {
            $extraArgs = @('+TIMBRE_TRACE_SHORT=results/logs/timbre_bank_short_trace.txt',
                           '+TIMBRE_TRACE_BOUNDARY=results/logs/timbre_bank_boundary_trace.txt',
                           '+TIMBRE_TRACE_ZERO=results/logs/timbre_bank_zero_trace.txt')
        }
        if ($top -eq 'tb_timbre_preview') {
            $extraArgs = @('+TIMBRE_PREVIEW=results/logs/timbre_preview.csv')
        }
        if ($top -eq 'tb_instrument_bank') {
            $extraArgs = @('+INSTRUMENT_TRACE_SHORT=results/logs/instrument_bank_short_trace.txt',
                           '+INSTRUMENT_TRACE_BOUNDARY=results/logs/instrument_bank_boundary_trace.txt',
                           '+INSTRUMENT_TRACE_ZERO=results/logs/instrument_bank_zero_trace.txt',
                           '+INSTRUMENT_TRACE_EXTREME=results/logs/instrument_bank_extreme_trace.txt')
        }
        if ($top -eq 'tb_instrument_preview') {
            $extraArgs = @('+INSTRUMENT_PREVIEW=results/logs/instrument_preview.csv')
        }
        # 负向对照保留独立波形，不能覆盖正常串行验证的波形。
        $waveName = if ($NegativeControl) { "${top}_negative" } else { $top }
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib -l $log -wlf "results/waves/$waveName.wlf" $top @extraArgs -do "do {$macro}"
        $exitCode = $LASTEXITCODE
        $logText = Get-Content -LiteralPath $log -Raw
        if ($exitCode -ne 0 -or $logText -match '(?m)^# \*\* (Fatal|Error):|(?m)^#\s*FAIL' -or -not $logText.Contains($markers[$top])) {
            throw "$top failed or did not finish all checks; see $log"
        }
        Write-Output "VERIFIED $top"
    }
    Write-Output "PASS: suite $Suite ($($tests.Count) testbenches)."
} finally { Pop-Location }
