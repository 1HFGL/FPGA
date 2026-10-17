[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',[switch]$NegativeControl,
      [ValidateSet('Mapping','Layout')][string]$Mutation='Mapping')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $out='build/regression/review'
    New-Item -ItemType Directory -Force $out | Out-Null
    $tag=if($NegativeControl){"negative_$Mutation"}else{'normal'}
    $lib="$out/${tag}_work"
    if(-not(Test-Path "$lib/_info")){& "$ModelSimBin/vlib.exe" $lib;if($LASTEXITCODE){throw 'vlib failed'}}
    $sources=@(rg --files rtl -g '*.v')+@(rg --files verification/tb/review -g '*.v')
    if($NegativeControl){
        $target=if($Mutation -eq 'Mapping'){'rtl/control/piano_controls.v'}else{'rtl/display/piano_display_renderer.v'}
        $original=Get-Content $target -Raw
        $mutated=if($Mutation -eq 'Mapping'){$original.Replace("gain_knob}+8'd16","gain_knob}+8'd15")}else{$original.Replace("KEY_W=WIDE?12'd120","KEY_W=WIDE?12'd119")}
        if($mutated -eq $original){throw 'Mutation target missing'}
        $mutated | Set-Content "$out/${Mutation}_mutation.v" -Encoding utf8
        $sources=@($sources | Where-Object {$_ -ne $target})+@("$out/${Mutation}_mutation.v")
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors')
    foreach($file in ($sources+@($PSCommandPath,'verification/data/display_font_golden.mem'))){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content "$out/${tag}_inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/${tag}_compile.log"
    if($LASTEXITCODE){throw 'Review compilation failed'}
    $tests=if($NegativeControl){if($Mutation -eq 'Mapping'){@('tb_review_arithmetic')}else{@('tb_review_layout')}}else{@('tb_review_arithmetic','tb_review_font','tb_review_layout')}
    foreach($test in $tests){
        $log="$out/${test}_${tag}.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/${test}_${tag}.wlf" $test -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$out/${test}_${tag}_console.log"
        $code=$LASTEXITCODE;$body=Get-Content $log -Raw
        if($NegativeControl){
            $expectedFailure=if($Mutation -eq 'Mapping'){'FAIL mapping'}else{'FAIL native pixel'}
            if($body -notmatch $expectedFailure -or $body.Contains("PASS $test")){throw 'Mutation was not rejected'}
            Write-Output "PASS negative control: $Mutation defect rejected"
        } else {
            if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or -not $body.Contains("PASS $test")){throw "Failed $test"}
            Write-Output "PASS $test"
        }
    }
}finally{Pop-Location}
