[CmdletBinding()]
param([string]$ModelSimBin='D:/Modelsim/win64')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
& (Join-Path $PSScriptRoot 'check_c_rtl.ps1') -ModelSimBin $ModelSimBin
if($LASTEXITCODE -ne 0){throw 'C strict compilation failed'}
$out=Join-Path $root 'build/regression/upstream-control'
$lib=Join-Path $root 'build/regression/upstream-rtl/work'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location (Split-Path -Parent $lib)
try {
foreach($test in @('tb_voice_control','tb_voice_control_16','tb_key_events','tb_input_fault_cleanup')) {
    $log=Join-Path $out "$test.log"
    & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -l $log "work.$test" -do 'onerror {quit -code 1 -f}; run -all; quit -code 0 -f' *> (Join-Path $out "${test}_console.log")
    $code=$LASTEXITCODE
    $body=Get-Content -LiteralPath $log -Raw
    if($code -ne 0 -or $body -match '\bFAIL:|\*\* (Fatal|Error):' -or $body -notmatch 'PASS:') {
        throw "C control test failed: $test ($log)"
    }
    Write-Output "PASS $test (strict Verilog library)"
}
} finally {Pop-Location}
