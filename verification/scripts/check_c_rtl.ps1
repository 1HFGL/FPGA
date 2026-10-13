[CmdletBinding()]
param([string]$ModelSimBin='C:\Library\modelsim\win64')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out=Join-Path $root 'build/regression/upstream-rtl'
foreach($tool in @('vlib','vlog')) {
    if(-not(Test-Path -LiteralPath "$ModelSimBin/$tool.exe")){throw "Missing ModelSim tool: $tool"}
}
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location $out
try {
    # 只编译C最新独立工程；旧A/B快照已删除，历史联合仿真从Git恢复。
    # 队友tb按用户要求原样保留，本入口只检查其Verilog RTL，不启用-sv。
    if(-not(Test-Path 'work/_info')) {
        & "$ModelSimBin/vlib.exe" work
        if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    }
    $sources=@(Get-ChildItem -LiteralPath "$root/upstream/fpga_interaction/rtl" -Filter '*.v' | Sort-Object FullName | ForEach-Object {$_.FullName})
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors; RTL only')
    foreach($file in $sources){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content 'inputs.txt' -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work work @sources *> 'compile.log'
    if($LASTEXITCODE -ne 0){throw "C RTL compilation failed: $out/compile.log"}
    Write-Output "PASS C snapshot RTL strict Verilog-2001: $($sources.Count) files; upstream testbenches unchanged and not executed."
} finally {Pop-Location}
