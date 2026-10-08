[CmdletBinding()]
param([ValidateSet('Uart','Legacy')][string]$Mode='Uart',
      [string]$Gowin='D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidence=Join-Path $root 'results/uart-basic-20261008'
if(-not(Test-Path -LiteralPath $Gowin)){throw "Missing Gowin: $Gowin"}
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$rom=Join-Path $root 'rtl/rom/sine_1024.mem'
if($Mode -eq 'Legacy'){
    # 仅机械转换GPRJ的相对引用；生成隔离复制品，不改原工程或下载文件。
    $projectDir=Join-Path $evidence 'legacy_rebuild'
    New-Item -ItemType Directory -Path "$projectDir/rtl/rom" -Force | Out-Null
    Copy-Item -LiteralPath $rom -Destination "$projectDir/rtl/rom/sine_1024.mem"
    [xml]$project=Get-Content (Join-Path $root 'fpga_project/fpga_project.gprj') -Raw
    foreach($node in $project.Project.FileList.File){
        $node.path=[IO.Path]::GetFullPath((Join-Path "$root/fpga_project" $node.path))
    }
    $projectPath=Join-Path $projectDir 'legacy_check.gprj'
    $project.Save($projectPath)
    $script='build_legacy.tcl'; $name='instrument_adsr_check'; $ports=8
}else{
    $projectDir=$PSScriptRoot
    $projectPath=Join-Path $projectDir 'uart_basic.gprj'
    [xml]$project=Get-Content $projectPath -Raw
    $script='build_uart.tcl'; $name='instrument_uart'; $ports=10
}
$inputs=@($rom,$projectPath,(Join-Path $PSScriptRoot $script),$PSCommandPath)
foreach($node in $project.Project.FileList.File){
    $inputs+=$(if([IO.Path]::IsPathRooted($node.path)){
        [IO.Path]::GetFullPath($node.path)
    }else{[IO.Path]::GetFullPath((Join-Path $projectDir $node.path))})
}
$lines=@("mode=$Mode target=GW5AT-LV60PG484AC1/I0/B")
foreach($inputFile in ($inputs | Select-Object -Unique)){
    $lines+="$((Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash)  $inputFile"
}
$lines | Set-Content "$evidence/${Mode}_build_inputs.txt" -Encoding utf8
Push-Location $PSScriptRoot
try {
    & $Gowin $script 2>&1 | Tee-Object "$evidence/${Mode}_build.log"
    if($LASTEXITCODE -ne 0){throw "Gowin $Mode failed"}
}finally{Pop-Location}
$log=Get-Content "$evidence/${Mode}_build.log" -Raw
if($log -match 'ERROR|EX3988|EX3791|EX3073'){throw 'Build contains an unresolved error/ROM/width/interface warning'}
$rptPath=Join-Path $projectDir "impl/pnr/$name.rpt.txt"
$timingPath=Join-Path $projectDir "impl/pnr/$name.tr"
$rpt=Get-Content $rptPath -Raw
$timing=Get-Content $timingPath -Raw
if($rpt -notmatch 'BSRAM\s*\|\s*4/118' -or $rpt -notmatch 'DSP\s*\|\s*8/118'){
    throw 'Audio ROM/DSP inference mismatch; do not program'
}
if(([regex]::Matches($rpt,'(?m)^\w+(?:\[\d+\])?\s*\|\s*-\s*\|\s*\w+/\d+\s*\|\s*Y\s*\|')).Count -ne $ports){
    throw 'Pin constraint coverage mismatch'
}
foreach($type in @('setup','hold')){
    if($timing -notmatch "sys_clk\s+$type\s+0\.000\s+0"){throw "$type violation or missing summary"}
}
foreach($line in $lines){
    if($line -match '^([A-F0-9]{64})  (.+)$'){
        if((Get-FileHash -LiteralPath $Matches[2]).Hash -ne $Matches[1]){throw "Input changed during build: $($Matches[2])"}
    }
}
Copy-Item -LiteralPath $rptPath,$timingPath -Destination $evidence
$bitstream=Join-Path $projectDir "impl/pnr/$name.fs"
@("file=$bitstream","sha256=$((Get-FileHash -LiteralPath $bitstream).Hash)",
  'Executed: synthesis, place/route, bitstream; NOT programmed or physically verified.',
  'Known limitations: PR1014, DAC external timing, UART real COM/MTBF, contest compliance/latency.') |
    Set-Content "$evidence/${Mode}_artifact.txt" -Encoding utf8
Write-Output "PASS $Mode build checks; hardware/complete external timing remain unverified."
