# 保存已运行的结果，不执行构建、仿真或下载；源文件变更后拒绝复用旧All结果。
[CmdletBinding()]
param([string]$Destination = 'build/regression/evidence-adsr')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $manifest = Get-Content -LiteralPath 'build/regression/logs/All_sha256.txt'
    foreach ($line in $manifest) {
        if ($line -match '^([A-F0-9]{64})  (.+)$') {
            $expectedHash = $Matches[1]
            $sourcePath = $Matches[2]
            if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $expectedHash) {
                throw "Source changed since All regression: $sourcePath"
            }
        }
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath 'build/regression/logs/All_sha256.txt' -Destination $Destination
    $tests = @('tb_phase_acc','tb_wave_lut','tb_voice_dds','tb_adsr_env','tb_adsr_arithmetic','tb_sample_gain',
        'tb_voice_adsr','sample_tick_tb','synth_top_tb','tb_single_tone_ab',
        'tb_input_sync_debounce','tb_pressure_if','tb_event_encoder','tb_voice_allocator',
        'tb_interaction_top','tb_voice_test_pattern','tb_demo_voice_bank','tb_instrument_demo',
        'tb_adsr_voice_bank','tb_sample_mixer4','tb_voice_bank_adsr',
        'tb_instrument_adsr','tb_allocator_trigger','tb_allocator_age','tb_allocator_owner',
        'tb_allocator_expression_owner','tb_allocator_expression_reset')
    foreach ($test in $tests) {
        $path = "build/regression/logs/$test.log"
        $log = Get-Content -LiteralPath $path -Raw
        if ($log -notmatch 'PASS' -or $log -match '\*\* (Fatal|Error):|(?m)^#\s*FAIL') {
            throw "Test did not pass: $test"
        }
        Copy-Item -LiteralPath $path -Destination $Destination
    }
    # 两个负向检查也须匹配当前源码，不能把旧故障日志当成本轮验证。
    foreach ($case in @(
        @{ Suite='ADSRDemo'; Top='tb_instrument_adsr'; Message='intentional ADSR serial mutation' },
        @{ Suite='ADSRMath'; Top='tb_adsr_arithmetic'; Message='ADSR attack arithmetic' }
    )) {
        $negativeManifest = "build/regression/logs/$($case.Suite)_negative_sha256.txt"
        foreach ($line in Get-Content -LiteralPath $negativeManifest) {
            if ($line -match '^([A-F0-9]{64})  (.+)$') {
                if ((Get-FileHash -LiteralPath $Matches[2] -Algorithm SHA256).Hash -ne $Matches[1]) {
                    throw "Negative-control source changed: $($Matches[2])"
                }
            }
        }
        $negativeLog = "build/regression/logs/$($case.Top)_negative.log"
        $logText = Get-Content -LiteralPath $negativeLog -Raw
        if ($logText -notmatch '\bFAIL\b' -or -not $logText.Contains($case.Message)) {
            throw "Expected negative control not observed: $($case.Top)"
        }
        Copy-Item -LiteralPath $negativeManifest,$negativeLog -Destination $Destination
    }
    $artifacts = @('projects/examples/adsr/fpga_project.gprj','projects/examples/adsr/impl/fpga_project_process_config.json',
        'projects/examples/adsr/build_adsr_demo.tcl','projects/examples/adsr/build_adsr_auto_demo.tcl',
        'boards/tang_mega_60k_31004/demo.cst','boards/tang_mega_60k_31004/demo.sdc',
        'model/check_dds.py','model/check_adsr.py','model/check_abc_demo.py','model/check_adsr_mix.py',
        'model/check_poly_adsr.py','verification/scripts/save_adsr_evidence.ps1')
    foreach ($name in @('instrument_adsr','instrument_adsr_auto')) {
        foreach ($extension in @('rpt.txt','tr')) {
            $path = "projects/examples/adsr/impl/pnr/$name.$extension"
            Copy-Item -LiteralPath $path -Destination $Destination
            $artifacts += $path
        }
        $artifacts += "projects/examples/adsr/impl/pnr/$name.fs"
    }
    # 旧渐变版已归档；若之后重新构建回退版，优先记录新生成的那一份。
    $legacyDemoFs = 'projects/examples/adsr/impl/pnr/instrument_demo.fs'
    if (-not (Test-Path -LiteralPath $legacyDemoFs)) {
        $legacyDemoFs = 'projects/legacy/pnr-20261007/instrument_demo.fs'
    }
    $artifacts += $legacyDemoFs
    $hashes = foreach ($artifact in $artifacts) {
        "$((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash)  $artifact"
    }
    $hashes | Set-Content -LiteralPath "$Destination/artifacts_sha256.txt" -Encoding ascii
    Write-Output "Saved $($tests.Count) regression logs, two negative controls, both implementation reports and artifact hashes to $Destination"
} finally { Pop-Location }
