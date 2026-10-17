[CmdletBinding()]
param([string]$Gowin='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',
      [string]$Python='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
      [switch]$PrepareOnly)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root 'build/hdmi'
if(-not(Test-Path -LiteralPath $Gowin)){throw "Missing Gowin: $Gowin"}
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $PSScriptRoot
try {
    # 同一生成步骤供GUI和命令行使用，避免两份公共引脚表逐渐不一致。
    & $Gowin build.tcl prepare *> "$out/prepare.log"
    if($LASTEXITCODE){throw 'Cannot prepare combined constraints'}
    if($PrepareOnly){Write-Output 'PASS prepared piano_hdmi.gprj (no compilation)';return}
    [xml]$project=Get-Content piano_hdmi.gprj -Raw
    $inputs=@($PSCommandPath,"$PSScriptRoot/build.tcl","$PSScriptRoot/piano_hdmi.gprj",
        "$root/verification/scripts/check_hdmi_implementation.py",
        "$PSScriptRoot/process_config.json","$root/rtl/rom/piano_1024.mem",
        "$root/rtl/rom/guitar_1024.mem","$root/rtl/rom/sine_1024.mem",
        "$root/rtl/rom/piano_v3_modes.mem","$root/rtl/rom/rock_v2_shaper.mem")
    $inputs+=@('piano.cst','piano.sdc','hdmi.cst','hdmi.sdc','hdmi_reset_placement.cst') | ForEach-Object {"$root/boards/tang_mega_60k_31004/$_"}
    foreach($node in $project.Project.FileList.File){$inputs+=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $node.path))}
    $manifest=@('top=piano_hdmi_top; sys=50MHz; pixel=49MHz; serial=245MHz; 1024x600 CVT candidate')
    foreach($file in ($inputs | Select-Object -Unique)){
        $manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"
    }
    $manifest | Set-Content "$out/build_inputs.txt" -Encoding utf8
    # Gowin 的 gw_sh 会派生综合/布局布线子进程；PowerShell 的 *> 有时只捕获父进程，
    # 于是日志停留在旧内容而退出码仍为 0。改由 cmd 层重定向，确保子进程输出完整落盘。
    # cmd 重定向写 UTF-16LE，随后再转成 UTF-8 供校验脚本读取。
    # 某些受限 PowerShell 环境没有 ComSpec 变量；显式回退到 cmd.exe。
    $hostExe=if([string]::IsNullOrEmpty($env:ComSpec)){'cmd.exe'}else{$env:ComSpec}
    $cmdLine=('"' + $Gowin + '" build.tcl > "' + $out + '/build.log" 2>&1')
    & $hostExe /c $cmdLine
    if($LASTEXITCODE){throw "Gowin failed: $out/build.log"}
    $log=Get-Content "$out/build.log" -Raw
    Set-Content "$out/build.log" -Value $log -Encoding utf8
    if($log -match 'ERROR|EX3988|EX3791|EX3073|TA2003'){throw 'Build has unresolved error, ROM, width, interface or constraint warning'}
    foreach($line in $manifest){
        if($line -match '^([A-F0-9]{64})  (.+)$'){
            if((Get-FileHash -LiteralPath $Matches[2]).Hash -ne $Matches[1]){throw "Input changed: $($Matches[2])"}
        }
    }
    $expected=(Get-FileHash process_config.json).Hash
    $effective=(Get-FileHash impl/piano_hdmi_process_config.json).Hash
    if($expected -ne $effective){throw 'Effective process options differ from controlled options'}
    $base=Join-Path $PSScriptRoot 'impl/pnr/piano_hdmi'
    & $Python "$root/projects/piano/read_timing_html.py" "${base}_tr_content.html" "$out/timing.txt"
    if($LASTEXITCODE){throw 'Cannot extract timing tables'}
    Copy-Item -LiteralPath "$base.rpt.txt","${base}_tr_content.html" -Destination $out
    if(Test-Path "$base.tr"){Copy-Item -LiteralPath "$base.tr" -Destination $out}
    @("file=$base.fs","sha256=$((Get-FileHash -LiteralPath "$base.fs").Hash)",
      "process_sha256=$effective",'Synthesis/PNR executed. Inspect all timing tables and constraint coverage.',
      'NOT programmed; no screen, touch, signal-integrity or end-to-end latency signoff.') |
        Set-Content "$out/artifact.txt" -Encoding utf8
    & $Python "$root/verification/scripts/check_hdmi_implementation.py" --directory $out
    if($LASTEXITCODE){throw "HDMI timing/coverage check failed: $out/implementation_check.json"}
    Write-Output 'PASS HDMI current constraints only; external timing/electrical/hardware checks still required.'
} finally {Pop-Location}
