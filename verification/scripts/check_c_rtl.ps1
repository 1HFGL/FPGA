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
    # 旧SV测试保留；此入口严格检查C RTL及三份Verilog控制测试，不启用-sv。
    if(-not(Test-Path 'work/_info')) {
        & "$ModelSimBin/vlib.exe" work
        if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    }
    $sources=@(Get-ChildItem -LiteralPath "$root/upstream/fpga_interaction/rtl" -Filter '*.v' | Sort-Object FullName | ForEach-Object {$_.FullName})
    $sources+=@("tb_voice_control.v","tb_key_events.v","tb_input_fault_cleanup.v" | ForEach-Object {Join-Path "$root/upstream/fpga_interaction/tb" $_})
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors; RTL only')
    foreach($file in $sources){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content 'inputs.txt' -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work work @sources *> 'compile.log'
    if($LASTEXITCODE -ne 0){throw "C RTL compilation failed: $out/compile.log"}
    Write-Output "PASS C snapshot RTL strict Verilog-2001: $($sources.Count) files; 15 RTL + 3 Verilog control test files; compilation only."
} finally {Pop-Location}
