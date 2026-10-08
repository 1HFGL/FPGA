# 保存已运行的结果，不执行构建、仿真或下载；源文件变更后拒绝复用旧All结果。
[CmdletBinding()]
param([string]$Destination = 'results/adsr-integration-20261002')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $manifest = Get-Content -LiteralPath 'results/logs/All_sha256.txt'
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
    Copy-Item -LiteralPath 'results/logs/All_sha256.txt' -Destination $Destination
    $tests = @('tb_phase_acc','tb_wave_lut','tb_voice_dds','tb_adsr_env','tb_adsr_arithmetic','tb_sample_gain',
        'tb_voice_adsr','sample_tick_tb','synth_top_tb','tb_single_tone_ab',
        'tb_input_sync_debounce','tb_pressure_if','tb_event_encoder','tb_voice_allocator',
        'tb_interaction_top','tb_voice_test_pattern','tb_demo_voice_bank','tb_instrument_demo',
        'tb_adsr_voice_bank','tb_sample_mixer4','tb_voice_bank_adsr',
        'tb_instrument_adsr','tb_allocator_trigger','tb_allocator_age','tb_allocator_owner',
        'tb_allocator_expression_owner','tb_allocator_expression_reset')
    foreach ($test in $tests) {
        $path = "results/logs/$test.log"
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
        $negativeManifest = "results/logs/$($case.Suite)_negative_sha256.txt"
        foreach ($line in Get-Content -LiteralPath $negativeManifest) {
            if ($line -match '^([A-F0-9]{64})  (.+)$') {
                if ((Get-FileHash -LiteralPath $Matches[2] -Algorithm SHA256).Hash -ne $Matches[1]) {
                    throw "Negative-control source changed: $($Matches[2])"
                }
            }
        }
        $negativeLog = "results/logs/$($case.Top)_negative.log"
        $logText = Get-Content -LiteralPath $negativeLog -Raw
        if ($logText -notmatch '\*\* Fatal:' -or -not $logText.Contains($case.Message)) {
            throw "Expected negative control not observed: $($case.Top)"
        }
        Copy-Item -LiteralPath $negativeManifest,$negativeLog -Destination $Destination
    }
    $artifacts = @('fpga_project/fpga_project.gprj','fpga_project/impl/fpga_project_process_config.json',
        'fpga_project/build_adsr_demo.tcl','fpga_project/build_adsr_auto_demo.tcl',
        'boards/tang_mega_60k_31004/demo.cst','boards/tang_mega_60k_31004/demo.sdc',
        'model/check_dds.py','model/check_adsr.py','model/check_abc_demo.py','model/check_adsr_mix.py',
        'model/check_poly_adsr.py','sim/save_adsr_evidence.ps1')
    foreach ($name in @('instrument_adsr','instrument_adsr_auto')) {
        foreach ($extension in @('rpt.txt','tr')) {
            $path = "fpga_project/impl/pnr/$name.$extension"
            Copy-Item -LiteralPath $path -Destination $Destination
            $artifacts += $path
        }
        $artifacts += "fpga_project/impl/pnr/$name.fs"
    }
    # 旧渐变版已归档；若之后重新构建回退版，优先记录新生成的那一份。
    $legacyDemoFs = 'fpga_project/impl/pnr/instrument_demo.fs'
    if (-not (Test-Path -LiteralPath $legacyDemoFs)) {
        $legacyDemoFs = 'fpga_project/legacy/pnr-20261007/instrument_demo.fs'
    }
    $artifacts += $legacyDemoFs
    $hashes = foreach ($artifact in $artifacts) {
        "$((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash)  $artifact"
    }
    $hashes | Set-Content -LiteralPath "$Destination/artifacts_sha256.txt" -Encoding ascii
    Write-Output "Saved $($tests.Count) regression logs, two negative controls, both implementation reports and artifact hashes to $Destination"
} finally { Pop-Location }
