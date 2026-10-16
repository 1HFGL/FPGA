[CmdletBinding()]
param(
    [ValidateSet('A','Wave','B','C','UART','Display','PA','All')][string]$Suite='A',
    [string]$ModelSimBin='D:/modelsim1/win64',
    [string]$Python='python'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    if($Suite -in @('A','All')) {
        & $Python verification/scripts/run_music_tests.py --bin $ModelSimBin
        if($LASTEXITCODE -ne 0){throw 'Music regression failed'}
        & $Python model/check_music_pipe.py build/regression/music/tb_music_pipe.csv
        if($LASTEXITCODE -ne 0){throw 'Sample oracle failed'}
        & $Python model/check_music_controls.py build/regression/music/tb_music_controls.csv
        if($LASTEXITCODE -ne 0){throw 'Control oracle failed'}
        & $Python model/check_music_range.py
        if($LASTEXITCODE -ne 0){throw 'Range audit failed'}
    }
    $tests=@()
    if($Suite -in @('Wave','All')) {$tests+=@('tb_phase_acc','tb_wave_lut','tb_voice_dds','tb_adsr_env','tb_adsr_arithmetic','tb_sample_gain','tb_voice_adsr','tb_sample_mixer4','tb_voice_bank_adsr','tb_wave_lut_timbre','tb_timbre_bank','tb_allocator_trigger')}
    if($Suite -in @('B','All')) {$tests+=@('sample_tick_tb','synth_top_tb','tb_audio_boundaries')}
    if($Suite -in @('C','All')) {$tests+=@('tb_input_sync_debounce','tb_event_encoder','tb_voice_allocator',
        'tb_allocator_age','tb_allocator_owner','tb_allocator_expression_owner','tb_allocator_expression_reset')}
    if($Suite -in @('UART','All')) {$tests+='tb_uart_bytes'}
    foreach($top in $tests) {
        $tb=if($top -in @('tb_allocator_age','tb_allocator_owner','tb_allocator_expression_owner','tb_allocator_expression_reset')){'verification/tb/control/tb_allocator_review.v'}else{
            $match=@(Get-ChildItem verification/tb -Recurse -Filter "$top.v")
            if($match.Count -ne 1){throw "Expected one test source: $top"}
            $match[0].FullName.Substring($root.Length+1)
        }
        $sources=@(Get-ChildItem rtl -Recurse -Filter '*.v' | Sort-Object FullName | ForEach-Object {$_.FullName.Substring($root.Length+1)})+@($tb)
        $marker=switch($top) {
            'tb_phase_acc' {'PASS: all 15 checks passed.'}
            'tb_wave_lut' {'PASS: all 1035 checks passed; all 1024 ROM addresses verified.'}
            'tb_voice_dds' {'PASS: voice_dds; 4810 valid samples matched; 1200025 clock checks passed.'}
            'tb_adsr_env' {'PASS: adsr_env duration checks'}
            'tb_adsr_arithmetic' {'PASS: adsr arithmetic exhaustive checks'}
            'tb_sample_gain' {'PASS: sample_gain exhaustive checks'}
            'tb_voice_adsr' {'PASS: voice_adsr sample and pipeline checks'}
            'tb_sample_mixer4' {'PASS: sample_mixer4 signed boundaries, saturation, idle and reset.'}
            'tb_voice_bank_adsr' {'PASS: voice_bank_adsr four independent envelopes, triggers, pipeline and mix.'}
            'tb_wave_lut_timbre' {'PASS: two timbre ROMs, idle/reset, direct threshold and R1 pipeline.'}
            'tb_timbre_bank' {'PASS: tb_timbre_bank'}
            'tb_allocator_trigger' {'PASS tb_allocator_trigger'}
            'tb_input_sync_debounce' {'PASS: tb_input_sync_debounce'}
            'tb_event_encoder' {'PASS: tb_event_encoder'}
            'tb_voice_allocator' {'PASS: tb_voice_allocator_32'}
            default {"PASS $top"}
        }
        & "$PSScriptRoot/run_modelsim.ps1" -ModelSimBin $ModelSimBin -Top $top -Sources $sources `
            -ExpectedPass $marker -OutputDirectory "build/regression/support/$top"
    }
    if($Suite -in @('Display','All')) {& "$PSScriptRoot/run_display_tests.ps1" -ModelSimBin $ModelSimBin}
    if($Suite -in @('PA','All')) {& "$PSScriptRoot/run_pa_tests.ps1" -ModelSimBin $ModelSimBin}
    Write-Output "PASS current suite $Suite"
}finally{Pop-Location}
