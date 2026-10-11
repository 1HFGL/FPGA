[CmdletBinding()]
param([string]$ModelSimBin='C:\Library\modelsim\win64')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    # 编译全部有效源码，不把历史报告或高云生成网表当手写 RTL。
    # Git 清单排除 Documents 下的厂商模板/缓存，同时包含尚未提交的新测试。
    $paths=@(git ls-files --cached --others --exclude-standard -- rtl sim tb fpga_project |
        Select-Object -Unique | Where-Object {$_ -match '\.(v|sv|svh)$' -and (Test-Path -LiteralPath $_)})
    if($LASTEXITCODE -ne 0){throw 'Cannot list project sources'}
    $files=@($paths | ForEach-Object {Get-Item -LiteralPath $_})
    $forbidden=@($files | Where-Object {$_.Extension -ne '.v'})
    if($forbidden.Count){throw "Only Verilog .v is allowed: $($forbidden.FullName -join ', ')"}
    $out='results/sync-review-20261011'
    $lib="$out/strict_work"
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    if(-not(Test-Path "$lib/_info")) {
        & "$ModelSimBin/vlib.exe" $lib
        if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    }
    $sources=@($files | Sort-Object FullName | ForEach-Object {$_.FullName})
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)", 'flags=-vlog01compat -pedanticerrors')
    foreach($file in $sources){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content "$out/strict_inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/strict_compile.log"
    if($LASTEXITCODE -ne 0){throw "Strict Verilog compilation failed: $out/strict_compile.log"}
    Write-Output "PASS strict Verilog-2001: $($sources.Count) files; no SystemVerilog mode."
} finally {Pop-Location}
