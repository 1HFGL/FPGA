[CmdletBinding()]
param([string]$ModelSimBin='D:/Modelsim/win64')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out=Join-Path $root 'build/keyboard-verification'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$shell='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
$runs=@(
    @{name='strict';script='check_verilog.ps1';args=@()},
    @{name='keyboard';script='run_keyboard_tests.ps1';args=@()},
    @{name='control';script='run_tests.ps1';args=@('-Suite','C')},
    @{name='piano';script='run_piano_tests.ps1';args=@()},
    @{name='uart';script='run_uart_tests.ps1';args=@()}
)
foreach($run in $runs) {
    $script=Join-Path $PSScriptRoot $run.script
    $extra=$run.args
    $log=@(& $shell -NoProfile -ExecutionPolicy Bypass -File $script -ModelSimBin $ModelSimBin @extra 2>&1)
    $code=$LASTEXITCODE
    $log | Set-Content -LiteralPath (Join-Path $out ($run.name+'.log')) -Encoding UTF8
    if($code -ne 0) {
        $log | Select-Object -Last 20 | Write-Output
        throw "Failed: $($run.name), exit=$code"
    }
    Write-Output "PASS $($run.name)"
}
