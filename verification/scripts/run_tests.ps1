[CmdletBinding()]
param(
    [ValidateSet('A','ADSR','ADSRMath','PolyADSR','Timbre','Instruments','PresetsBoard','B','C','AB','Review','All')][string]$Suite = 'A',
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [switch]$NegativeControl
)
$ErrorActionPreference = 'Stop'
if ($NegativeControl -and $Suite -notin @('AB','ADSRMath','PresetsBoard')) {
    throw 'NegativeControl requires AB, ADSRMath or PresetsBoard.'
}
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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
    tb_event_encoder = 'PASS: tb_event_encoder'
    tb_voice_allocator = 'PASS: tb_voice_allocator_32'
    tb_allocator_trigger = 'PASS tb_allocator_trigger'
    tb_allocator_age = 'PASS tb_allocator_age:'
    tb_allocator_owner = 'PASS tb_allocator_owner:'
    tb_allocator_expression_owner = 'PASS tb_allocator_expression_owner:'
    tb_allocator_expression_reset = 'PASS tb_allocator_expression_reset:'
}
if ($Suite -in @('A','ADSR','AB','All')) {
    if ($Suite -ne 'ADSR') { $tests += @('tb_phase_acc','tb_wave_lut','tb_voice_dds') }
    $sources += @('rtl/synth/phase_acc.v','rtl/synth/wave_lut.v','rtl/synth/voice_dds.v','verification/tb/synth/tb_phase_acc.v','verification/tb/synth/tb_wave_lut.v','verification/tb/synth/tb_voice_dds.v')
}
if ($Suite -in @('A','ADSR','All')) {
    $tests += @('tb_adsr_env','tb_sample_gain','tb_voice_adsr')
    # 单独运行 ADSR 时，也必须显式编译 voice_adsr 依赖的 DDS 模块。
    $sources += @('rtl/synth/phase_acc.v','rtl/synth/wave_lut.v','rtl/synth/voice_dds.v',
                  'rtl/synth/adsr_env.v','rtl/synth/sample_gain.v','rtl/synth/voice_adsr.v',
                  'verification/tb/synth/tb_adsr_env.v','verification/tb/synth/tb_sample_gain.v','verification/tb/synth/tb_voice_adsr.v')
}
if ($Suite -in @('A','ADSR','ADSRMath','All')) {
    $sources += @('rtl/synth/adsr_env.v','verification/tb/synth/tb_adsr_arithmetic.v')
    $tests += 'tb_adsr_arithmetic'
}
if ($Suite -in @('A','PolyADSR','All')) {
    $tests += @('tb_sample_mixer4','tb_voice_bank_adsr','tb_allocator_trigger')
    $sources += @('rtl/synth/phase_acc.v','rtl/synth/wave_lut.v','rtl/synth/voice_dds.v',
                  'rtl/synth/adsr_env.v','rtl/synth/sample_gain.v','rtl/synth/voice_adsr.v',
                  'rtl/control/note_phase_lut.v','rtl/synth/sample_mixer4.v','rtl/synth/voice_bank_adsr.v',
                  'rtl/synth/wave_lut_timbre.v','rtl/synth/voice_timbre_adsr.v',
                  'verification/tb/synth/tb_sample_mixer4.v','verification/tb/synth/tb_voice_bank_adsr.v',
                  'rtl/control/voice_allocator.v','verification/tb/control/tb_allocator_trigger.v')
}
if ($Suite -in @('A','Timbre','All')) {
    $tests += @('tb_wave_lut_timbre','tb_timbre_bank','tb_timbre_preview')
    $sources += @('rtl/synth/phase_acc.v','rtl/synth/wave_lut.v','rtl/synth/wave_lut_timbre.v',
                  'rtl/synth/adsr_env.v','rtl/synth/sample_gain.v','rtl/synth/voice_timbre_adsr.v',
                  'rtl/control/note_phase_lut.v','rtl/synth/sample_mixer4.v','rtl/synth/voice_bank_adsr.v',
                  'verification/tb/synth/tb_wave_lut_timbre.v','verification/tb/synth/tb_timbre_bank.v','verification/tb/synth/tb_timbre_preview.v')
}
if ($Suite -in @('A','Instruments','All')) {
    $tests += @('tb_instrument_wave','tb_instrument_bank','tb_instrument_preview')
    $sources += @('rtl/synth/phase_acc.v','rtl/synth/wave_lut.v','rtl/synth/instrument_wave.v',
                  'rtl/synth/instrument_env.v','rtl/synth/sample_gain.v','rtl/synth/voice_instrument.v',
                  'rtl/control/note_phase_lut.v','rtl/synth/sample_mixer4.v','rtl/synth/voice_bank_instruments.v',
                  'verification/tb/synth/tb_instrument_wave.v','verification/tb/synth/tb_instrument_bank.v','verification/tb/synth/tb_instrument_preview.v')
}
if ($Suite -in @('PresetsBoard','All')) {
    $tests += 'tb_instrument_presets'
    $sources += @('rtl/top/instrument_presets_top.v','rtl/control/input_sync_debounce.v',
                  'rtl/audio/synth_top.v','rtl/audio/sample_tick.v','rtl/audio/i2s_tx.v',
                  'rtl/synth/phase_acc.v','rtl/synth/wave_lut.v','rtl/synth/instrument_wave.v',
                  'rtl/synth/instrument_env.v','rtl/synth/sample_gain.v','rtl/synth/voice_instrument.v',
                  'rtl/control/note_phase_lut.v','rtl/synth/sample_mixer4.v','rtl/synth/voice_bank_instruments.v',
                  'verification/tb/integration/tb_instrument_presets.v')
}
if ($Suite -in @('B','AB','All')) {
    $tests += @('sample_tick_tb','synth_top_tb')
    $sources += @('rtl/audio/sample_tick.v','rtl/audio/i2s_tx.v','rtl/audio/synth_top.v','verification/tb/audio/sample_tick_tb.v','verification/tb/audio/synth_top_tb.v')
}
if ($Suite -in @('AB','All')) {
    $tests += 'tb_single_tone_ab'
    $sources += @('verification/tb/integration/single_tone_demo_top.v','verification/tb/integration/tb_single_tone_ab.v')
}
if ($Suite -in @('C','All')) {
    $cModules = @('input_sync_debounce','touch_or_key_if','event_encoder','voice_allocator')
    $cTests = @('tb_input_sync_debounce','tb_event_encoder','tb_voice_allocator')
    foreach($name in $cModules){
        $found=@(Get-ChildItem -LiteralPath "$root/rtl" -Filter "$name.v" -Recurse)
        if($found.Count -ne 1){throw "Expected one active RTL module: $name"}
        $sources+=$found[0].FullName.Substring($root.Length+1).Replace('\','/')
    }
    foreach($name in $cTests){
        $found=@(Get-ChildItem -LiteralPath "$root/verification/tb" -Filter "$name.v" -Recurse)
        if($found.Count -ne 1){throw "Expected one active Verilog test: $name"}
        $sources+=$found[0].FullName.Substring($root.Length+1).Replace('\','/')
    }
    $tests += $cTests
}
# 仅保留当前声部分配器回归；已退役实现的专用测试随旧实现删除。
if ($Suite -in @('C','Review','All')) {
    $sources += @('rtl/control/voice_allocator.v','verification/tb/control/tb_allocator_review.v')
    $tests += @('tb_allocator_age','tb_allocator_owner','tb_allocator_expression_owner','tb_allocator_expression_reset')
}
$sources = @($sources | Select-Object -Unique)
Push-Location $root
try {
    New-Item -ItemType Directory -Path 'build/regression/logs','build/regression/waves' -Force | Out-Null
    # ROM 虽不由 vlog 直接编译，仍是功能输入；记录本次所有源码/波表哈希。
    $manifestInputs = @($sources) + @('verification/scripts/run_tests.ps1')
    if ($Suite -in @('A','ADSR','PolyADSR','Timbre','Instruments','PresetsBoard','AB','All')) { $manifestInputs += 'rtl/rom/sine_1024.mem' }
    if ($Suite -in @('A','PolyADSR','Timbre','All')) { $manifestInputs += 'rtl/rom/bright_1024.mem' }
    if ($Suite -in @('A','Instruments','PresetsBoard','All')) { $manifestInputs += @('rtl/rom/guitar_1024.mem','rtl/rom/strings_1024.mem') }
    $manifestName = if ($NegativeControl) { "${Suite}_negative_sha256.txt" } else { "${Suite}_sha256.txt" }
    $manifestLines = @("suite=$Suite negative_control=$NegativeControl")
    foreach ($source in $manifestInputs) {
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $manifestLines += "$hash  $source"
    }
    $manifestLines | Set-Content -LiteralPath "build/regression/logs/$manifestName" -Encoding ascii
    # 负向验证使用独立工作库，避免污染正常回归的编译产物。
    $lib = if ($NegativeControl) { 'build/regression/regression_negative_work' } else { 'build/regression/regression_work' }
    if (-not (Test-Path -LiteralPath "$lib/_info")) {
        & (Join-Path $ModelSimBin 'vlib.exe') $lib
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed.' }
    }
    $compileArgs = @('-vlog01compat','-pedanticerrors')
    if ($NegativeControl) {
        $compileArgs += $(if ($Suite -eq 'AB') { '+define+AB_NEGATIVE_CONTROL' }
            elseif ($Suite -eq 'ADSRMath') { '+define+ADSR_ARITH_NEGATIVE_CONTROL' }
            else { '+define+PRESETS_BOARD_NEGATIVE_CONTROL' })
    }
    & (Join-Path $ModelSimBin 'vlog.exe') @compileArgs -work $lib @sources
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
    foreach ($top in $tests) {
        $macro = "build/regression/logs/${top}_run.do"
        @"
onerror {quit -code 1 -f}
onbreak {quit -code 0 -f}
# 老 A 测试使用 stop；日志必须含 PASS 且不含 FAIL，不能只看退出码。
# 原 DDS 双音高用例需要略多于 100ms；1s 是异常未结束的兜底上限。
run 1 sec
quit -code 0 -f
"@ | Set-Content -LiteralPath $macro -Encoding ascii
        $log = if ($NegativeControl) {
            "build/regression/logs/${top}_negative.log"
        } else {
            "build/regression/logs/$top.log"
        }
        $extraArgs = @()
        if ($top -eq 'tb_voice_dds') { $extraArgs = @('+DDS_TRACE=build/regression/logs/dds_trace.txt') }
        if ($top -eq 'tb_voice_adsr') { $extraArgs = @('+ADSR_TRACE=build/regression/logs/adsr_trace.txt') }
        if ($top -eq 'tb_voice_bank_adsr') {
            $extraArgs = @('+POLY_TRACE_DEFAULT=build/regression/logs/poly_adsr_default_trace.txt',
                           '+POLY_TRACE_BOUNDARY=build/regression/logs/poly_adsr_boundary_trace.txt')
        }
        if ($top -eq 'tb_timbre_bank') {
            $extraArgs = @('+TIMBRE_TRACE_SHORT=build/regression/logs/timbre_bank_short_trace.txt',
                           '+TIMBRE_TRACE_BOUNDARY=build/regression/logs/timbre_bank_boundary_trace.txt',
                           '+TIMBRE_TRACE_ZERO=build/regression/logs/timbre_bank_zero_trace.txt')
        }
        if ($top -eq 'tb_timbre_preview') {
            $extraArgs = @('+TIMBRE_PREVIEW=build/regression/logs/timbre_preview.csv')
        }
        if ($top -eq 'tb_instrument_bank') {
            $extraArgs = @('+INSTRUMENT_TRACE_SHORT=build/regression/logs/instrument_bank_short_trace.txt',
                           '+INSTRUMENT_TRACE_BOUNDARY=build/regression/logs/instrument_bank_boundary_trace.txt',
                           '+INSTRUMENT_TRACE_ZERO=build/regression/logs/instrument_bank_zero_trace.txt',
                           '+INSTRUMENT_TRACE_EXTREME=build/regression/logs/instrument_bank_extreme_trace.txt')
        }
        if ($top -eq 'tb_instrument_preview') {
            $extraArgs = @('+INSTRUMENT_PREVIEW=build/regression/logs/instrument_preview.csv')
        }
        # 负向对照保留独立波形，不能覆盖正常串行验证的波形。
        $waveName = if ($NegativeControl) { "${top}_negative" } else { $top }
        & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $lib -l $log -wlf "build/regression/waves/$waveName.wlf" $top @extraArgs -do "do {$macro}"
        $exitCode = $LASTEXITCODE
        $logText = Get-Content -LiteralPath $log -Raw
        if ($exitCode -ne 0 -or $logText -match '(?m)^# \*\* (Fatal|Error):|(?m)^#\s*FAIL' -or -not $logText.Contains($markers[$top])) {
            throw "$top failed or did not finish all checks; see $log"
        }
        Write-Output "VERIFIED $top"
    }
    Write-Output "PASS: suite $Suite ($($tests.Count) testbenches)."
} finally { Pop-Location }
