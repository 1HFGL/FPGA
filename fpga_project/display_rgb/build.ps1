[CmdletBinding()]
param([string]$Gowin='D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe',
      [string]$EvidenceDirectory='results/display-20261013/synthesis')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root $EvidenceDirectory
if(-not(Test-Path $Gowin)){throw "Missing Gowin: $Gowin"}
New-Item -ItemType Directory -Path $out -Force | Out-Null
[xml]$project=Get-Content "$PSScriptRoot/display_rgb.gprj" -Raw
$sources=@("$PSScriptRoot/display_rgb.gprj","$PSScriptRoot/synthesize.tcl",$PSCommandPath)
foreach($node in $project.Project.FileList.File){$sources+=Join-Path $PSScriptRoot $node.path}
$manifest=@('top=instrument_display; device=GW5AT-LV60PG484AC1/I0/B; synthesis only')
foreach($source in $sources){$manifest+="$((Get-FileHash -LiteralPath $source).Hash)  $source"}
$manifest | Set-Content "$out/inputs.txt" -Encoding utf8
Push-Location $PSScriptRoot
try {
    & $Gowin synthesize.tcl 2>&1 | Tee-Object "$out/build.log"
    if($LASTEXITCODE -ne 0){throw 'Display synthesis failed'}
} finally {Pop-Location}
$log=Get-Content "$out/build.log" -Raw
if($log -match '\bERROR\b|EX3791|EX3073' -or $log -notmatch 'PASS display RTL synthesis only'){
    throw 'Missing successful synthesis marker'
}
foreach($entry in $manifest){
    if($entry -match '^([A-F0-9]{64})  (.+)$'){
        if((Get-FileHash -LiteralPath $Matches[2]).Hash -ne $Matches[1]){throw 'Source changed during synthesis'}
    }
}
Write-Output 'Verified synthesis log. Pinout, PLL, CDC constraints and external timing remain pending.'
