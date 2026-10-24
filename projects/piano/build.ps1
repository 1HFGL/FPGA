[CmdletBinding()]
param([string]$Gowin='D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe',
      [string]$EvidenceDirectory='build/piano',
      [string]$Python='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
      [switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidence=if([IO.Path]::IsPathRooted($EvidenceDirectory)){
    [IO.Path]::GetFullPath($EvidenceDirectory)
}else{[IO.Path]::GetFullPath((Join-Path $root $EvidenceDirectory))}
if(-not(Test-Path -LiteralPath $Gowin)){throw "Missing Gowin: $Gowin"}
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$projectPath=Join-Path $PSScriptRoot 'uart_piano.gprj'
$processConfigPath=Join-Path $PSScriptRoot 'process_config.json'
$effectiveConfigPath=Join-Path $PSScriptRoot 'impl/uart_piano_process_config.json'
if(-not(Test-Path -LiteralPath $processConfigPath -PathType Leaf)){
    throw "Missing controlled process configuration: $processConfigPath"
}
$expectedConfigHash=(Get-FileHash -LiteralPath $processConfigPath).Hash
[xml]$project=Get-Content -LiteralPath $projectPath -Raw
$inputs=@($projectPath,$PSCommandPath,$processConfigPath,(Join-Path $PSScriptRoot 'build_piano.tcl'),
    (Join-Path $root 'rtl/rom/piano_1024.mem'),
    (Join-Path $root 'rtl/rom/guitar_1024.mem'),(Join-Path $root 'rtl/rom/sine_1024.mem'),
    (Join-Path $root 'rtl/rom/piano_v3_modes.mem'),(Join-Path $root 'rtl/rom/rock_v2_shaper.mem'),
    (Join-Path $root 'host/tone_examples/piano.json'),
    (Join-Path $root 'host/studio_model.py'))
foreach($node in $project.Project.FileList.File){
    $inputs+=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $node.path))
}
$inputs+=Join-Path $root 'projects/check_modal_rom.tcl'
$inputs+=Get-ChildItem -LiteralPath "$root/rtl/rom" -Filter 'piano_v3_modes.mem.bank*.mem' | ForEach-Object {$_.FullName}
$lines=@('top=piano_performance_top voices=16 target=GW5AT-LV60PG484AC1/I0/B clock=50MHz')
foreach($file in ($inputs | Select-Object -Unique)){
    $lines+="$((Get-FileHash -LiteralPath $file).Hash)  $file"
}
$lines | Set-Content "$evidence/build_inputs.txt" -Encoding utf8
if(-not $CheckOnly) {
    Push-Location $PSScriptRoot
    try {
        & $Gowin 'build_piano.tcl' 2>&1 | Tee-Object "$evidence/build.log"
        if($LASTEXITCODE -ne 0){throw 'Gowin build failed'}
    }finally{Pop-Location}
}
# 记录工具实际留下的配置；不能只给受控输入做哈希，却仍采用旧impl选项。
if(-not(Test-Path -LiteralPath $effectiveConfigPath -PathType Leaf)){
    throw "Missing effective process configuration: $effectiveConfigPath"
}
$effectiveConfigHash=(Get-FileHash -LiteralPath $effectiveConfigPath).Hash
Copy-Item -LiteralPath $effectiveConfigPath -Destination (Join-Path $evidence 'effective_process_config.json')
@("controlled=$processConfigPath","controlled_sha256=$expectedConfigHash",
  "effective=$effectiveConfigPath","effective_sha256=$effectiveConfigHash") |
    Set-Content (Join-Path $evidence 'process_config_hashes.txt') -Encoding utf8
if($effectiveConfigHash -ne $expectedConfigHash){
    throw 'Effective process configuration differs from controlled input; inspect process_config_hashes.txt'
}
$log=Get-Content "$evidence/build.log" -Raw
if($log -match 'ERROR|EX3988|EX3791|EX3073'){throw 'Unresolved error/ROM/width/interface warning; do not program'}
$base=Join-Path $PSScriptRoot 'impl/pnr/piano_performance'
$rpt=Get-Content "$base.rpt.txt" -Raw
$normalizedTiming=Join-Path $evidence 'timing_from_html.txt'
& $Python (Join-Path $PSScriptRoot 'read_timing_html.py') "${base}_tr_content.html" $normalizedTiming
if($LASTEXITCODE -ne 0){throw 'Cannot read all HTML timing tables'}
$timing=Get-Content $normalizedTiming -Raw
$netlist=Get-Content (Join-Path $PSScriptRoot 'impl/gwsynthesis/piano_performance.vg') -Raw
# 模态参数ROM与相位/幅度状态映射片内RAM，共享运算器取代每声部复制乘法器。
$dsp=[regex]::Match($rpt,'DSP\s*\|\s*(\d+(?:\.\d+)?)/118')
$bsram=[regex]::Match($rpt,'BSRAM\s*\|\s*(\d+)/118')
if(-not $bsram.Success -or [int]$bsram.Groups[1].Value -lt 1 -or
    -not $dsp.Success -or [double]$dsp.Groups[1].Value -lt 1 -or [double]$dsp.Groups[1].Value -gt 32 -or
    $netlist -notmatch 'u_modal' -or $netlist -notmatch 'u_mode_rom' -or
    $netlist -notmatch 'bank0' -or $netlist -notmatch 'bank1' -or $netlist -notmatch 'bank2'){
    throw 'Modal RAM/DSP inference mismatch or legacy synthesis path still active'
}
if(([regex]::Matches($rpt,'(?m)^\w+(?:\[\d+\])?\s*\|\s*-\s*\|\s*\w+/\d+\s*\|\s*Y\s*\|')).Count -ne 25){
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
if(([regex]::Matches($timing,'(?m)^\s*TC_\w+\s+Actived\s+')).Count -ne 10){throw 'Constraint activation mismatch'}
foreach($line in $lines){
    if($line -match '^([A-F0-9]{64})  (.+)$'){
        if((Get-FileHash -LiteralPath $Matches[2]).Hash -ne $Matches[1]){throw "Input changed during build: $($Matches[2])"}
    }
}
Copy-Item -LiteralPath "$base.rpt.txt","${base}_tr_content.html" -Destination $evidence
foreach($node in $project.Project.FileList.File) {
    $designFile=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $node.path))
    if((Get-Item -LiteralPath $designFile).LastWriteTimeUtc -gt (Get-Item -LiteralPath "$base.fs").LastWriteTimeUtc) {
        throw "Implementation predates design input: $designFile"
    }
}
@("file=$base.fs","sha256=$((Get-FileHash -LiteralPath "$base.fs").Hash)",
  'Executed: synthesis, place/route, bitstream; NOT programmed or physically verified.',
  'Candidate only: PR1014 and complete DAC external timing remain unresolved; real COM/audio/latency unverified.') |
    Set-Content "$evidence/artifact.txt" -Encoding utf8
Write-Output 'PASS piano implementation checks; not full external timing/hardware signoff.'
