[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',
      [string]$OutputDirectory='build/b-review-20261013/pa-drain')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
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
    # 只取实际钢琴工程清单，避免与并行开发中的其他tb混编。
    $projectDir=Join-Path $root 'fpga_project/uart_piano'
    [xml]$project=Get-Content "$projectDir/uart_piano.gprj" -Raw
    $sources=@($project.Project.FileList.File | Where-Object {$_.type -eq 'file.verilog'} |
        ForEach-Object {[IO.Path]::GetFullPath((Join-Path $projectDir $_.path))})
    $sources+=@('sim/tb_uart_pa_drain.v')
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)", 'flags=-vlog01compat -pedanticerrors')
    foreach($file in ($sources+@('rtl/rom/piano_1024.mem',$PSCommandPath))) {
        $manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"
    }
    $manifest | Set-Content "$OutputDirectory/inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$OutputDirectory/compile.log"
    if($LASTEXITCODE -ne 0){throw 'PA test compile failed'}
    foreach($short in @(1,0)) {
        $log="$OutputDirectory/pa_short_$short.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$OutputDirectory/pa_short_$short.wlf" `
            tb_uart_pa_drain "-gSHORT_TAIL=$short" -do 'run -all; quit -code 0 -f' *> "$OutputDirectory/console_$short.log"
        $code=$LASTEXITCODE; $body=Get-Content -LiteralPath $log -Raw
        if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or
            -not $body.Contains("PASS tb_uart_pa_drain short=$short")) {throw "PA_DRAIN failed: $log"}
        Write-Output "PASS tb_uart_pa_drain short=$short"
    }
} finally {Pop-Location}
