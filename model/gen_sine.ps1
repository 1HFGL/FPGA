[CmdletBinding()]
param([string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'rtl/rom/sine_1024.mem'))
$ErrorActionPreference = 'Stop'
$lines = for ($k = 0; $k -lt 1024; $k++) {
    $value = [int][Math]::Round(32767.0 * [Math]::Sin(2.0 * [Math]::PI * $k / 1024.0), [MidpointRounding]::AwayFromZero)
    '{0:X4}' -f ($value -band 65535)
}
[IO.File]::WriteAllLines($OutputPath, [string[]]$lines, [Text.Encoding]::ASCII)
Write-Output "Generated 1024 signed 16-bit samples: $OutputPath"
