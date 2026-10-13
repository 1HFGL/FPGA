[CmdletBinding()]
param(
    [string]$ModelSimBin='C:/Library/modelsim/win64',
    [string]$OutputDirectory='build/regression/audio-parameters',
    [ValidateRange(-1,14)][int]$Case=-1
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $out.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'OutputDirectory must be a repository subdirectory'
}
New-Item -ItemType Directory -Path $out -Force | Out-Null
foreach($tool in @('vlib.exe','vlog.exe','vsim.exe')){
    if(-not(Test-Path -LiteralPath (Join-Path $ModelSimBin $tool))){throw "Missing tool: $ModelSimBin/$tool"}
}
$names=@('valid_legacy','valid_lead2','lead64','lead_negative','clock_zero','sample_rate_zero',
    'frequency_product_overflow32','slot_zero','slot_above16384','window_equals_R4','window_less_R4',
    'slot_negative','latency_zero','unsupported_sample_bits','valid_minimum_window5')
$legal=@(0,1,14)
if($Case -eq -1){
    # 默认自测通过子进程调用同一普通入口，明确检查非法用例真正返回非零。
    # 不能catch一切异常就PASS：同时要求正确的RTL拒绝标记，编译/工具故障不算通过。
    $shell=(Get-Process -Id $PID).Path
    $summary=foreach($id in 0..14){
        $childOut="$OutputDirectory/case$id"
        $console=Join-Path $out "case${id}_console.log"
        & $shell -NoProfile -File $PSCommandPath -ModelSimBin $ModelSimBin -OutputDirectory $childOut -Case $id *> $console
        $code=$LASTEXITCODE
        $log=Join-Path $root "$childOut/simulation.log"
        if(-not(Test-Path -LiteralPath $log)){throw "Case $id has no simulation evidence: $console"}
        $body=Get-Content -LiteralPath $log -Raw
        if($legal -contains $id){
            if($code -ne 0 -or -not $body.Contains("PASS tb_audio_parameters case=$id ")){
                throw "Legal case $id failed: $console"
            }
            $verdict='accepted'
        } else {
            $guard=if($id -in @(9,10,12,13)){'FAIL synth_top insufficient sample preparation window or unsupported format'}
                else{'FAIL sample_tick invalid timing parameters'}
            if($code -eq 0 -or -not $body.Contains($guard) -or $body.Contains('UNEXPECTED_ACCEPT')){
                throw "Illegal case $id was not explicitly rejected by the intended RTL guard: $console"
            }
            $verdict='explicitly_rejected'
        }
        Write-Host "VERIFIED case=$id $($names[$id]) $verdict exit=$code"
        [pscustomobject]@{case=$id;name=$names[$id];verdict=$verdict;exit_code=$code;log=$log}
    }
    $summary | Export-Csv -LiteralPath (Join-Path $out 'summary.csv') -NoTypeInformation -Encoding utf8
    Write-Output 'PASS check_audio_parameters: 3 legal cases accepted; 12 illegal cases explicitly rejected with nonzero exit.'
    exit 0
}

Push-Location $root
try{
    $lib=$out.Substring($root.Length+1).Replace('\','/')+'/work'
    $sources=@(foreach($name in @('sample_tick.v','synth_top.v','i2s_tx.v')){
        $found=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl') -Recurse -Filter $name)
        if($found.Count -ne 1){throw "Expected one active source named $name"}
        $found[0].FullName
    })+@((Join-Path $root 'verification/tb/integration/tb_audio_parameters.v'))
    $manifest=@("UTC=$([DateTime]::UtcNow.ToString('o'))","GitHEAD=$(git rev-parse HEAD)",
        "ModelSim=$(& "$ModelSimBin/vsim.exe" -version)","Case=$Case Name=$($names[$Case])",
        'Flags=-vlog01compat -pedanticerrors')
    foreach($source in ($sources+@($PSCommandPath))){$manifest+="$((Get-FileHash -LiteralPath $source).Hash)  $source"}
    $manifest | Set-Content -LiteralPath (Join-Path $out 'inputs.txt') -Encoding utf8
    & "$ModelSimBin/vlib.exe" $lib *> (Join-Path $out 'vlib.log')
    if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> (Join-Path $out 'compile.log')
    if($LASTEXITCODE -ne 0){throw "Strict Verilog compilation failed: $out/compile.log"}
    & "$ModelSimBin/vsim.exe" -c -lib $lib -l "$out/simulation.log" -wlf "$out/simulation.wlf" tb_audio_parameters "-gCASE_ID=$Case" -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f'
    $code=$LASTEXITCODE;$body=Get-Content -LiteralPath "$out/simulation.log" -Raw
    if($code -ne 0 -or $body -match '\*\* (Fatal|Error):|\bFAIL\b|UNEXPECTED_ACCEPT' -or
        -not $body.Contains("PASS tb_audio_parameters case=$Case ")){
        throw "Parameter case $Case rejected or failed: $out/simulation.log"
    }
    Write-Output "PASS case=$Case $($names[$Case])"
}finally{Pop-Location}
