[CmdletBinding()]
param([string]$ModelSimBin='D:/modelsim1/win64',[string]$Python='python')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    & $Python model/check_tone_filter.py generate
    if($LASTEXITCODE){throw 'Vector generation failed'}
    $cases=@(
        @('tb_tone_filter','verification/tb/audio/tb_tone_filter.v'),
        @('tb_brightness_keys','verification/tb/control/tb_brightness_keys.v'),
        @('tb_performance_brightness','verification/tb/integration/tb_performance_brightness.v'),
        @('tb_expression_modal','verification/tb/integration/tb_expression_modal.v')
    )
    $rtl=@(rg --files rtl -g '*.v')
    foreach($case in $cases) {
        & "$PSScriptRoot/run_modelsim.ps1" -ModelSimBin $ModelSimBin -Top $case[0] `
            -Sources ($rtl+@($case[1])) -ExpectedPass ("PASS "+$case[0]) `
            -OutputDirectory ("build/expression/"+$case[0])
    }
    & $Python model/check_tone_filter.py check
    if($LASTEXITCODE){throw 'Expression oracle/spectrum failed'}
    Write-Output 'PASS expression regression'
}finally{Pop-Location}
