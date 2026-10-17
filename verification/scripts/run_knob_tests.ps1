[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',
      [string]$OutputDirectory='build/regression/knob', [switch]$NegativeControl)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $tag=if($NegativeControl){'slow_wait'}else{'normal'}
    $out="$OutputDirectory/$tag"
    New-Item -ItemType Directory -Force $out | Out-Null
    $lib="$out/work"
    if(-not(Test-Path "$lib/_info")){& "$ModelSimBin/vlib.exe" $lib;if($LASTEXITCODE){throw 'vlib failed'}}
    $sources=@(rg --files rtl -g '*.v')+@('verification/tb/review/ads1115_timed_model.v','verification/tb/review/tb_review_knob_latency.v')
    if($NegativeControl){
        $target='rtl/control/ads1115_knob_if.v'
        $original=Get-Content $target -Raw
        $mutated=$original.Replace('CONV_WAIT     = (CLK_HZ / 2000) * 3','CONV_WAIT     = CLK_HZ / 100')
        if($original -eq $mutated){throw 'Mutation target missing'}
        $mutated | Set-Content "$out/slow_wait.v" -Encoding utf8
        $sources=@($sources | Where-Object {$_ -ne $target})+@("$out/slow_wait.v")
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors')
    foreach($file in ($sources+@($PSCommandPath))){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content "$out/inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/compile.log"
    if($LASTEXITCODE){throw "Knob compile failed: $out/compile.log"}
    & "$ModelSimBin/vsim.exe" -c -lib $lib -l "$out/latency.log" -wlf "$out/latency.wlf" tb_review_knob_latency -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$out/console.log"
    $code=$LASTEXITCODE; $body=Get-Content "$out/latency.log" -Raw
    if($NegativeControl){
        if($body -notmatch 'FAIL knob latency' -or $body -match 'PASS tb_review_knob_latency'){throw 'Slow-wait mutation survived'}
        Write-Output 'PASS negative control: slow conversion wait rejected by latency deadline'
    }else{
        if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or $body -notmatch 'PASS tb_review_knob_latency'){
            throw "Knob test failed: $out/latency.log"
        }
        $body -split "`n" | Where-Object {$_ -match 'KNOB|PASS tb_review_knob_latency'} | Write-Output
    }
}finally{Pop-Location}
