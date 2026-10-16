[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',
      [string]$OutputDirectory='build/regression/pa-drain')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    foreach($tool in @('vlib','vlog','vsim')) {
        if(-not(Test-Path -LiteralPath "$ModelSimBin/$tool.exe")){throw "Missing ModelSim: $tool"}
    }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $lib="$OutputDirectory/work"
    if(-not(Test-Path -LiteralPath "$lib/_info")) {
        & "$ModelSimBin/vlib.exe" $lib
        if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    }
    # 检查当前16声部钢琴核心，保留短尾音和默认尾音的DAC/功放排空断言。
    $sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl') -Recurse -Filter '*.v' |
        Sort-Object FullName | ForEach-Object {$_.FullName})
    $sources+=@('verification/tb/integration/tb_uart_pa_drain.v')
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)", 'flags=-vlog01compat -pedanticerrors')
    foreach($file in ($sources+@(Get-ChildItem 'rtl/rom' -Filter '*.mem' | ForEach-Object {$_.FullName})+@($PSCommandPath))) {
        $manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"
    }
    $manifest | Set-Content "$OutputDirectory/inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$OutputDirectory/compile.log"
    if($LASTEXITCODE -ne 0){throw 'PA test compile failed'}
    foreach($lead in @(60)) { foreach($short in @(1,0)) {
        $tag="lead${lead}_short${short}"
        $log="$OutputDirectory/pa_$tag.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$OutputDirectory/pa_$tag.wlf" `
            tb_uart_pa_drain "-gSHORT_TAIL=$short" "-gREQUEST_LEAD_HALF_EDGES=$lead" `
            -do 'run -all; quit -code 0 -f' *> "$OutputDirectory/console_$tag.log"
        $code=$LASTEXITCODE; $body=Get-Content -LiteralPath $log -Raw
        if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or
            -not $body.Contains("PASS tb_uart_pa_drain short=$short")) {throw "PA_DRAIN failed: $log"}
        Write-Output "PASS tb_uart_pa_drain lead=$lead short=$short"
    } }
} finally {Pop-Location}
