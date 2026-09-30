[CmdletBinding()]
param([string]$ModelSimBin = $env:MODELSIM_BIN)
# C 旧入口转到统一脚本；不再假定 D:\Modelsim 已安装。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'sim/run_tests.ps1') -Suite C -ModelSimBin $ModelSimBin
