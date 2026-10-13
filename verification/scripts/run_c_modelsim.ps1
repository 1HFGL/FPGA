[CmdletBinding()]
param([string]$SimDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# 仅兼容转发队友原始入口，不改它的SV测试/作者本机路径，也不作为主工程验收。
Write-Warning 'Upstream historical runner uses SystemVerilog and its original tool paths. For active Verilog-only checks use run_tests.ps1 -Suite C.'
$upstream=Join-Path $root 'upstream/fpga_interaction/scripts/run_modelsim.ps1'
if(-not(Test-Path -LiteralPath $upstream)){throw "Missing upstream runner: $upstream"}
& $upstream -SimDirectory $SimDirectory
