[CmdletBinding()]
param([string]$ModelSimBin='D:/Modelsim/win64')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out='build/regression/keyboard'
$lib="$out/work"
Push-Location $root
try {
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    if(-not(Test-Path "$lib/_info")) {
        & "$ModelSimBin/vlib.exe" $lib
        if($LASTEXITCODE -ne 0) {throw 'vlib failed'}
    }
    $sources=@(rg --files rtl -g '*.v')+@('verification/tb/integration/tb_piano_13_keys.v','verification/tb/integration/tb_piano_13_debounce.v')
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/compile.log"
    if($LASTEXITCODE -ne 0) {throw "compile failed: $out/compile.log"}
    foreach($test in @('tb_piano_13_keys','tb_piano_13_debounce')) {
        & "$ModelSimBin/vsim.exe" -c -onfinish exit -lib $lib -l "$out/${test}.log" $test -do 'onerror {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$out/${test}_console.log"
        $code=$LASTEXITCODE
        $body=Get-Content "$out/${test}.log" -Raw
        if($code -ne 0 -or $body -match '\*\* (Fatal|Error):|\bFAIL\b' -or -not $body.Contains("PASS ${test}:")) {
            throw "keyboard test failed: $out/${test}.log"
        }
        Write-Output "PASS $test"
    }
} finally {Pop-Location}
