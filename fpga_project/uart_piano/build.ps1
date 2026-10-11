[CmdletBinding()]
param([string]$Gowin='D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe',
      [string]$EvidenceDirectory='results/sync-review-20261011/build-piano')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidence=Join-Path $root $EvidenceDirectory
if(-not(Test-Path -LiteralPath $Gowin)){throw "Missing Gowin: $Gowin"}
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$projectPath=Join-Path $PSScriptRoot 'uart_piano.gprj'
[xml]$project=Get-Content -LiteralPath $projectPath -Raw
$inputs=@($projectPath,$PSCommandPath,(Join-Path $PSScriptRoot 'build_piano.tcl'),
    (Join-Path $root 'rtl/rom/piano_1024.mem'),
    (Join-Path $root 'fpga_music_tool/tone_examples/piano.json'),
    (Join-Path $root 'fpga_music_tool/studio_model.py'))
foreach($node in $project.Project.FileList.File){
    $inputs+=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $node.path))
}
$lines=@('top=instrument_uart_piano_top target=GW5AT-LV60PG484AC1/I0/B clock=50MHz')
foreach($file in ($inputs | Select-Object -Unique)){
    $lines+="$((Get-FileHash -LiteralPath $file).Hash)  $file"
}
$lines | Set-Content "$evidence/build_inputs.txt" -Encoding utf8
Push-Location $PSScriptRoot
try {
    & $Gowin 'build_piano.tcl' 2>&1 | Tee-Object "$evidence/build.log"
    if($LASTEXITCODE -ne 0){throw 'Gowin build failed'}
}finally{Pop-Location}
$log=Get-Content "$evidence/build.log" -Raw
if($log -match 'ERROR|EX3988|EX3791|EX3073'){throw 'Unresolved error/ROM/width/interface warning; do not program'}
$base=Join-Path $PSScriptRoot 'impl/pnr/instrument_uart_piano'
$rpt=Get-Content "$base.rpt.txt" -Raw
$timing=Get-Content "$base.tr" -Raw
if($rpt -notmatch 'BSRAM\s*\|\s*4/118' -or $rpt -notmatch 'DSP\s*\|\s*8/118'){
    throw 'Audio ROM/DSP inference mismatch'
}
if(([regex]::Matches($rpt,'(?m)^\w+(?:\[\d+\])?\s*\|\s*-\s*\|\s*\w+/\d+\s*\|\s*Y\s*\|')).Count -ne 10){
    throw 'Pin coverage mismatch'
}
foreach($type in @('setup','hold')){
    if($timing -notmatch "sys_clk\s+$type\s+0\.000\s+0"){throw "$type violation or missing summary"}
}
# 检查四类路径和脉宽的最差表；不是只看Setup/Hold两个总数。
foreach($section in @('3.1.1 Setup Paths Table','3.1.2 Hold Paths Table',
    '3.1.3 Recovery Paths Table','3.1.4 Removal Paths Table','3.2 Minimum Pulse Width Table')){
    $start=$timing.IndexOf("`n$section")
    if($start -lt 0){throw "Missing timing table: $section"}
    $table=$timing.Substring($start+1)
    $end=$table.IndexOf("`n`n")
    if($end -ge 0){$table=$table.Substring(0,$end)}
    $rows=[regex]::Matches($table,'(?m)^\s*\d+\s+(-?\d+\.\d+)\s+')
    if($rows.Count -eq 0){throw "No timing rows: $section"}
    foreach($row in $rows){
        if([double]::Parse($row.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){
            throw "Negative slack: $section"
        }
    }
}
if(([regex]::Matches($timing,'(?m)^\s*TC_\w+\s+Actived\s+')).Count -ne 6){throw 'Constraint activation mismatch'}
foreach($line in $lines){
    if($line -match '^([A-F0-9]{64})  (.+)$'){
        if((Get-FileHash -LiteralPath $Matches[2]).Hash -ne $Matches[1]){throw "Input changed during build: $($Matches[2])"}
    }
}
Copy-Item -LiteralPath "$base.rpt.txt","$base.tr" -Destination $evidence
@("file=$base.fs","sha256=$((Get-FileHash -LiteralPath "$base.fs").Hash)",
  'Executed: synthesis, place/route, bitstream; NOT programmed or physically verified.',
  'Candidate only: PR1014 and complete DAC external timing remain unresolved; real COM/audio/latency unverified.') |
    Set-Content "$evidence/artifact.txt" -Encoding utf8
Write-Output 'PASS piano implementation checks; not full external timing/hardware signoff.'
