[CmdletBinding()]
param([ValidateSet('Examples','Checks','Instruments','All')][string]$Group='All',
    [string]$Gowin='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',
    [string]$EvidenceDirectory='build/implementation-matrix')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(-not(Test-Path -LiteralPath $Gowin)){throw "Missing Gowin: $Gowin"}
$jobs=@(@(
    @('Examples','examples/adsr','build_demo.tcl','fpga_project.gprj','instrument_demo'),
    @('Examples','examples/adsr','build_auto_demo.tcl','fpga_project.gprj','instrument_demo_auto'),
    @('Examples','examples/adsr','build_adsr_auto_demo.tcl','fpga_project.gprj','instrument_adsr_auto'),
    @('Examples','examples/adsr','build_adsr_demo.tcl','fpga_project.gprj','instrument_adsr'),
    @('Checks','checks/poly_adsr_check','run.tcl','poly_adsr_check.gprj','poly_adsr_check'),
    @('Checks','checks/instruments_check','run.tcl','instruments_check.gprj','instruments_check'),
    @('Instruments','examples/instruments_board','run.tcl','instruments_board.gprj','instruments_board')
) | Where-Object {$Group -eq 'All' -or $_[0] -eq $Group})
$evidence=[IO.Path]::GetFullPath((Join-Path $root $EvidenceDirectory))
if(-not $evidence.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'EvidenceDirectory must be inside the repository'
}
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
# 四种旧演示共享一份工程，逐个执行；保全原受跟踪的impl配置并在最后恢复。
$savedConfig=Join-Path $evidence 'adsr_impl_config_before.json'
$adsrConfig=Join-Path $PSScriptRoot 'examples/adsr/impl/fpga_project_process_config.json'
$restore=($Group -in @('All','Examples')) -and (Test-Path -LiteralPath $adsrConfig)
if($restore){Copy-Item -LiteralPath $adsrConfig -Destination $savedConfig}
try {
    foreach($job in $jobs){
        $dir=Join-Path $PSScriptRoot $job[1]; $name=$job[4]
        $out=Join-Path $evidence $name
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        $gprj=Join-Path $dir $job[3]; [xml]$project=Get-Content -LiteralPath $gprj -Raw
        $inputs=@($PSCommandPath,$gprj,(Join-Path $dir $job[2]),(Join-Path $dir 'process_config.json'))
        foreach($file in $project.Project.FileList.File){
            $inputs+=[IO.Path]::GetFullPath((Join-Path $dir $file.path))
        }
        $inputs+=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl/rom') -File | ForEach-Object {$_.FullName})
        $hashes=@($inputs | Select-Object -Unique | ForEach-Object {Get-FileHash -LiteralPath $_})
        @("UTC=$([DateTime]::UtcNow.ToString('o'))","GitHEAD=$(git -C $root rev-parse HEAD)",
          "Command=$Gowin $($job[2]); working_directory=$dir")+
          @($hashes | ForEach-Object {"$($_.Hash)  $($_.Path)"}) |
            Set-Content -LiteralPath "$out/inputs.txt" -Encoding utf8
        Push-Location $dir
        try{
            & $Gowin $job[2] *> "$out/build.log"
            if($LASTEXITCODE -ne 0){throw "Gowin failed: $name"}
        }finally{Pop-Location}
        $log=Get-Content -LiteralPath "$out/build.log" -Raw
        if($log -match '\bERROR\b|EX3988|EX3791|EX3073' -or $log -notmatch 'PASS'){
            throw "Missing successful implementation or unresolved error: $out/build.log"
        }
        $base=Join-Path $dir "impl/pnr/$name"
        $report=Get-Content -LiteralPath "$base.rpt.txt" -Raw
        $timing=Get-Content -LiteralPath "$base.tr" -Raw
        foreach($type in @('setup','hold')){
            if($timing -notmatch "\s$type\s+0\.000\s+0"){throw "Timing violation/missing $type summary: $name"}
        }
        # 逐个最差表检查，而非将未分析路径误记作通过。
        foreach($section in @('3.1.1 Setup Paths Table','3.1.2 Hold Paths Table',
            '3.1.3 Recovery Paths Table','3.1.4 Removal Paths Table','3.2 Minimum Pulse Width Table')){
            $start=$timing.IndexOf("`n$section")
            if($start -lt 0){throw "Missing table: $name $section"}
            $table=$timing.Substring($start+1);$end=$table.IndexOf("`n`n")
            if($end -ge 0){$table=$table.Substring(0,$end)}
            $rows=[regex]::Matches($table,'(?m)^\s*\d+\s+(-?\d+\.\d+)\s+')
            # 无异步复位的独立check可能没有recovery/removal路径，需显式记录N/A。
            if($rows.Count -eq 0 -and $section -notmatch 'Recovery|Removal'){throw "No timing rows: $name $section"}
            foreach($row in $rows){
                if([double]::Parse($row.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){
                    throw "Negative timing slack: $name $section"
                }
            }
        }
        if($timing -notmatch '\sActived\s'){throw "No active constraints: $name"}
        foreach($hash in $hashes){
            if((Get-FileHash -LiteralPath $hash.Path).Hash -ne $hash.Hash){throw "Input changed: $($hash.Path)"}
        }
        Copy-Item -LiteralPath "$base.rpt.txt","$base.tr" -Destination $out
        @("bitstream=$base.fs","sha256=$((Get-FileHash -LiteralPath "$base.fs").Hash)",
          'PASS existing constrained paths only; no programming; PR1014/external DAC timing may remain.') |
            Set-Content -LiteralPath "$out/artifact.txt" -Encoding utf8
        Write-Output "PASS implementation $name"
    }
}finally{
    if($restore){Copy-Item -LiteralPath $savedConfig -Destination $adsrConfig}
}
