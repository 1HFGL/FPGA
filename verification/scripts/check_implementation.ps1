[CmdletBinding()]
param([string]$Gowin='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',
      [string]$Python='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
      [switch]$PrepareOnly,
      [switch]$SelfTestLog)
$ErrorActionPreference='Stop'
# 原多工程矩阵已移除；统一委托主工程的综合、实现及约束检查流程。
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
& (Join-Path $root 'projects/hdmi/build.ps1') -Gowin $Gowin -Python $Python `
    -PrepareOnly:$PrepareOnly -SelfTestLog:$SelfTestLog
