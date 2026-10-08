[CmdletBinding()]
param([string]$ModelSimBin='C:\Library\modelsim\win64', [switch]$NegativeControl)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'results/piano-20261008'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$tag=if($NegativeControl){'negative'}else{'normal'}
# ModelSim10.6e的-lib传相对库目录；含盘符的绝对路径会被vopt误读为模块名。
$lib='results/piano-20261008/'+$(if($NegativeControl){'negative_work'}else{'work'})
Push-Location $root
try {
    if(-not(Test-Path "$lib/_info")){
        & "$ModelSimBin/vlib.exe" $lib
        if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    }
    $sources=@(Get-ChildItem rtl -Filter '*.v' | ForEach-Object {$_.FullName})
    $sources+=@('sim/tb_piano_tone.sv','sim/tb_uart_piano_board.sv')
    $manifest=@("ModelSim=$(& "$ModelSimBin/vsim.exe" -version)")
    foreach($file in ($sources+@('rtl/rom/piano_1024.mem','rtl/rom/sine_1024.mem',$PSCommandPath))){
        $manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"
    }
    $manifest | Set-Content "$out/${tag}_sim_inputs.txt" -Encoding utf8
    $argsList=@('-sv','-work',$lib)
    if($NegativeControl){$argsList+='+define+PIANO_NEGATIVE_CONTROL'}
    & "$ModelSimBin/vlog.exe" @argsList @sources *> "$out/${tag}_compile.log"
    if($LASTEXITCODE -ne 0){throw "compile failed: $out/${tag}_compile.log"}
    $tests=if($NegativeControl){@('tb_piano_tone')}else{@('tb_piano_tone','tb_uart_piano_board')}
    foreach($test in $tests){
        $log="$out/${test}_${tag}.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/${test}_${tag}.wlf" $test -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f'
        $code=$LASTEXITCODE; $body=Get-Content -LiteralPath $log -Raw
        # ModelSim有时$ fatal仍返回0；同时检查日志，不能只依赖退出码。
        if($code -ne 0 -or $body -match '\*\* (Fatal|Error):|\bFAIL\b' -or -not $body.Contains("PASS $test")){
            throw "$test failed: $log"
        }
        Write-Output "VERIFIED $test"
    }
} finally {Pop-Location}
