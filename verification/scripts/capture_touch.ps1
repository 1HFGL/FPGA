param([int]$Seconds=120)
$ErrorActionPreference='Stop'
if($Seconds -lt 1 -or $Seconds -gt 180){throw 'Capture must be bounded to 1..180 seconds'}
$captureRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$captureOutput=Join-Path $captureRoot 'build/touch_driver_20261024'
New-Item -ItemType Directory -Force $captureOutput | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot 'TouchCapture.cs') -ReferencedAssemblies System.Windows.Forms
[TouchCapture]::Run((Join-Path $captureOutput 'touch_reports.jsonl'),$Seconds)
