[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',[switch]$NegativeControl)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $out='build/regression/dual';New-Item -ItemType Directory -Force $out | Out-Null
    $tag=if($NegativeControl){'negative'}else{'normal'};$lib="$out/${tag}_work"
    if(-not(Test-Path "$lib/_info")){& "$ModelSimBin/vlib.exe" $lib;if($LASTEXITCODE){throw 'vlib failed'}}
    $sources=@(rg --files rtl -g '*.v')+@(rg --files verification/tb/review -g 'tb_review_dual*.v')
    if($NegativeControl){
        $target='rtl/top/instrument_uart_top.v';$original=Get-Content $target -Raw
        $needle='.voice_timbre(bank_timbre)'
        if(-not $original.Contains($needle)){throw 'Dual mutation target missing'}
        $original.Replace($needle,".voice_timbre({VOICES{1'b0}})") | Set-Content "$out/dual_mutation.v" -Encoding utf8
        $sources=@($sources|Where-Object{$_ -ne $target})+@("$out/dual_mutation.v")
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors')
    foreach($file in ($sources+@($PSCommandPath)+@(Get-ChildItem rtl/rom -Filter '*.mem'|ForEach-Object FullName))){$manifest+="$((Get-FileHash $file).Hash)  $file"}
    $manifest | Set-Content "$out/${tag}_inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/${tag}_compile.log"
    if($LASTEXITCODE){throw 'Dual strict compilation failed'}
    $tests=if($NegativeControl){@('tb_review_dual_system')}else{@('tb_review_dual_math','tb_review_dual_voice','tb_review_dual_system')}
    foreach($test in $tests){
        $log="$out/${test}_${tag}.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/${test}_${tag}.wlf" $test -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$out/${test}_${tag}_console.log"
        $code=$LASTEXITCODE;$body=Get-Content $log -Raw
        if($NegativeControl){
            if($body -notmatch 'FAIL dual synthesis guitar selection not connected' -or $body.Contains("PASS $test")){throw 'Dual timbre defect not rejected'}
            Write-Output 'PASS dual negative control: disconnected guitar selection rejected'
        }else{
            if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):|Failed to open|readmem.*failed' -or -not $body.Contains("PASS $test")){throw "Failed $test : $log"}
            Write-Output "PASS $test"
        }
    }
}finally{Pop-Location}
