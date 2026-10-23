[CmdletBinding()]
param(
    [ValidateRange(1,8)][int]$Jobs=3,
    [string[]]$Rules=@('0:0','2:0','2:1','3:1','4:1'),
    [ValidateSet(0,1)][int[]]$ClockOrders=@(0),
    [ValidateSet('balanced','setup')][string]$Rank='balanced',
    [string]$Gowin='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',
    [string]$Python='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
    [ValidateRange(1,120)][int]$TimeoutMinutes=30,
    [switch]$ConfirmBest,
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
foreach($tool in @($Gowin,$Python)){
    if(-not(Test-Path -LiteralPath $tool)){throw "Missing executable: $tool"}
}
$arguments=@("$root/verification/scripts/pnr_sweep.py",'--jobs',"$Jobs",'--gowin',$Gowin,
    '--rank',$Rank,'--timeout',"$($TimeoutMinutes*60)",'--rules')+$Rules+
    @('--clock-orders')+@($ClockOrders | ForEach-Object {"$_"})
if($ConfirmBest){$arguments+='--confirm-best'}
if($PrepareOnly){$arguments+='--prepare-only'}
& $Python @arguments
exit $LASTEXITCODE
