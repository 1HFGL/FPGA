[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',
      [string]$OutputDirectory='build/regression/performance',
      [string[]]$Tests=@('tb_performance_bank','tb_performance_system','tb_performance_adc','tb_performance_control','tb_performance_latency'),
      [ValidateSet('None','Volume','Bend')][string]$Mutation='None')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $out="$OutputDirectory/$Mutation"
    $lib="$out/work"
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    if(-not(Test-Path "$lib/_info")) { & "$ModelSimBin/vlib.exe" $lib; if($LASTEXITCODE){throw 'vlib failed'} }
    $sources=@(rg --files rtl -g '*.v')+@(rg --files verification/tb/integration -g '*performance*.v')
    if($LASTEXITCODE){throw 'source discovery failed'}
    if($Mutation -ne 'None') {
        $original=Get-Content rtl/top/instrument_uart_top.v -Raw
        $needle=if($Mutation -eq 'Volume'){'.gain(gain_d4)'}else{'.bend_ratio(bend_ratio),'}
        $replacement=if($Mutation -eq 'Volume'){".gain(17'd65536)"}else{".bend_ratio(18'd65536),"}
        if(-not $original.Contains($needle)){throw 'Mutation target missing'}
        $mutated=$original.Replace($needle,$replacement)
        # 生成的故障副本只写build；正式RTL和队友tb不动。
        $mutated | Set-Content "$out/mutated_top.v" -Encoding utf8
        $sources=@($sources | Where-Object {$_ -ne 'rtl/top/instrument_uart_top.v'})+@("$out/mutated_top.v")
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors')
    foreach($file in $sources){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content "$out/inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/compile.log"
    if($LASTEXITCODE){throw "Compile failed: $out/compile.log"}
    foreach($test in $Tests){
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l "$out/${test}.log" -wlf "$out/${test}.wlf" $test -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$out/${test}_console.log"
        $code=$LASTEXITCODE
        $body=Get-Content "$out/${test}.log" -Raw
        $failed=$code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal)' -or -not $body.Contains("PASS ${test}:")
        if($Mutation -eq 'None'){
            if($failed){throw "Test failed: $out/${test}.log"}
            Write-Output "PASS $test"
        }else{
            if(-not $failed -or $body -notmatch '\bFAIL: (master gain not connected|top mute|ADC did not mute|ADC did not bend)'){
                throw "Mutation not rejected by intended audio checker: $out/${test}.log"
            }
            Write-Output "PASS negative control: $Mutation rejected by $test"
        }
    }
}finally{Pop-Location}
