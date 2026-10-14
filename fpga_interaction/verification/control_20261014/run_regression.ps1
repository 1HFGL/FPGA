$ErrorActionPreference='Stop'
$verificationRoot=$PSScriptRoot
$cRoot=Split-Path (Split-Path $verificationRoot -Parent) -Parent
$filesRoot=Split-Path $cRoot -Parent
$shellPath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$cOutput=@(& $shellPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $cRoot 'scripts/run_modelsim.ps1') -SimDirectory (Join-Path $verificationRoot 'sim') 2>&1)
$cExit=$LASTEXITCODE
$cOutput | Set-Content -LiteralPath (Join-Path $verificationRoot 'simulation.log') -Encoding UTF8
$cPasses=@($cOutput | Select-String -Pattern 'PASS:').Count
Write-Output "C exit=$cExit PASS=$cPasses"
if($cExit -ne 0 -or $cPasses -ne 17) {
    $cOutput | Select-Object -Last 25 | Write-Output
    exit 1
}
$abOutput=@(& $shellPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $filesRoot 'fpga_ab_sim/scripts/run_modelsim.ps1') 2>&1)
$abExit=$LASTEXITCODE
$abOutput | Set-Content -LiteralPath (Join-Path $verificationRoot 'ab_simulation.log') -Encoding UTF8
$abPasses=@($abOutput | Select-String -Pattern 'PASS:').Count
Write-Output "AB exit=$abExit PASS=$abPasses"
if($abExit -ne 0 -or $abPasses -ne 8) {
    $abOutput | Select-Object -Last 25 | Write-Output
    exit 1
}
