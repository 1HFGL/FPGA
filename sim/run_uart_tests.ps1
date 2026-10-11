[CmdletBinding()]
param([string]$ModelSimBin='C:\Library\modelsim\win64',
      [string[]]$Tests=@('tb_uart_bytes','tb_uart_line','tb_uart_protocol','tb_uart_flow','tb_uart_replies','tb_uart_instrument','tb_uart_instrument_115200'),
      [switch]$NegativeControl, [switch]$SourceMutation,
      [string]$OutputDirectory='results/sync-review-20261011/uart')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $out=$OutputDirectory
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    if($NegativeControl -and $SourceMutation){throw 'Choose one negative mode'}
    $tag=if($SourceMutation){'source_mutation'}elseif($NegativeControl){'negative'}else{'normal'}
    $lib="$out/${tag}_work"
    if(-not(Test-Path "$lib/_info")){
        & "$ModelSimBin/vlib.exe" $lib
        if($LASTEXITCODE -ne 0){ throw 'vlib failed' }
    }
    $sources=@(Get-ChildItem rtl -Filter '*.v' | ForEach-Object { 'rtl/'+$_.Name })
    $sources+=@(Get-ChildItem sim -Filter 'tb_uart*.v' | ForEach-Object { 'sim/'+$_.Name })
    if($SourceMutation){
        # 在结果副本里故意把所有PC来源映射成0，正式源文件绝不改动。
        $original=Get-Content -LiteralPath 'rtl/uart_event_arbiter.v' -Raw
        $needle="{1'b1,pc_note}"
        if(([regex]::Matches($original,[regex]::Escape($needle))).Count -ne 1){throw 'Mutation target changed'}
        $mutated="$out/source_mutation_arbiter.v"
        $original.Replace($needle,"8'd0") | Set-Content -LiteralPath $mutated -Encoding utf8
        $sources=@($sources | Where-Object {$_ -ne 'rtl/uart_event_arbiter.v'})+@($mutated)
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vsim.exe" -version)")
    foreach($file in ($sources+@('rtl/rom/sine_1024.mem','sim/run_uart_tests.ps1'))){
        $manifest+="$((Get-FileHash $file -Algorithm SHA256).Hash)  $file"
    }
    $manifest | Set-Content "$out/${tag}_inputs.txt" -Encoding utf8
    $argsList=@('-vlog01compat','-pedanticerrors','-work',$lib)
    if($NegativeControl){$argsList+='+define+UART_NEGATIVE_CONTROL'}
    & "$ModelSimBin/vlog.exe" @argsList @sources 2>&1 | Tee-Object "$out/${tag}_compile.log"
    if($LASTEXITCODE -ne 0){ throw 'UART compilation failed' }
    foreach($test in $Tests){
        $log="$out/${test}_${tag}.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/${test}_${tag}.wlf" $test -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f'
        $code=$LASTEXITCODE
        $body=Get-Content $log -Raw
        if($code -ne 0 -or $body -match '\*\* (Fatal|Error):|\bFAIL\b' -or -not $body.Contains("PASS $test")){
            throw "$test failed; see $log"
        }
        Write-Output "VERIFIED $test"
    }
} finally { Pop-Location }
