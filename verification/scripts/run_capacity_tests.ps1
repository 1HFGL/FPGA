[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',
      [string[]]$Tests=@('tb_review_uart_capacity','tb_review_uart_capacity_top'),[switch]$NegativeControl)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $out='build/regression/capacity'
    New-Item -ItemType Directory -Force $out | Out-Null
    $tag=if($NegativeControl){'negative'}else{'normal'}
    $lib="$out/${tag}_work"
    if(-not(Test-Path "$lib/_info")){& "$ModelSimBin/vlib.exe" $lib;if($LASTEXITCODE){throw 'vlib failed'}}
    $sources=@(rg --files rtl -g '*.v')+@(rg --files verification/tb/review -g 'tb_review_uart_capacity*.v')
    if($NegativeControl){
        $target='rtl/top/instrument_uart_top.v'
        $original=Get-Content $target -Raw
        $needle='.FIXED_PIANO(FIXED_PIANO),.VOICES(VOICES)) u_uart'
        if(-not $original.Contains($needle)){throw 'Capacity mutation target missing'}
        $original.Replace($needle,'.FIXED_PIANO(FIXED_PIANO),.VOICES(4)) u_uart') |
            Set-Content "$out/capacity_mutation.v" -Encoding utf8
        $sources=@($sources | Where-Object {$_ -ne $target})+@("$out/capacity_mutation.v")
        $Tests=@('tb_review_uart_capacity_top')
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors')
    foreach($file in ($sources+@($PSCommandPath,'rtl/rom/piano_1024.mem','rtl/rom/guitar_1024.mem','rtl/rom/sine_1024.mem'))){$manifest+="$((Get-FileHash $file).Hash)  $file"}
    $manifest | Set-Content "$out/${tag}_inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/${tag}_compile.log"
    if($LASTEXITCODE){throw 'Capacity compilation failed'}
    foreach($test in $Tests){
        $log="$out/${test}_${tag}.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/${test}_${tag}.wlf" $test -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$out/${test}_${tag}_console.log"
        $code=$LASTEXITCODE;$body=Get-Content $log -Raw
        if($NegativeControl){
            if($body -notmatch 'FAIL capacity top byte' -or $body.Contains("PASS $test")){throw 'Capacity defect was not rejected'}
            Write-Output 'PASS capacity negative control: disconnected parameter rejected'
        }else{
            if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or -not $body.Contains("PASS $test")){throw "Failed $test : $log"}
            Write-Output "PASS $test"
        }
    }
}finally{Pop-Location}
