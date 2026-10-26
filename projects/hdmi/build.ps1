[CmdletBinding()]
param([string]$Gowin='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',
      [string]$Python='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
      [switch]$PrepareOnly,
      [switch]$SelfTestLog)
$ErrorActionPreference='Stop'
# 只把日志级别ERROR或既有禁用告警码视作失败；数组名errors不是工具报错。
$buildFailurePattern='(?m)^\s*ERROR\b|EX3988|EX3791|EX3073|TA2003|AG0101'
if($SelfTestLog){
    $cases=@(
        @{Log="Extracting RAM for identifier 'errors'";Reject=$false},
        @{Log="Extracting RAM for identifier 'ERRORS'";Reject=$false},
        @{Log='ERROR (EX0001) : invalid module';Reject=$true},
        @{Log=('normal line'+[Environment]::NewLine+'  Error (PR0004) : unrouted nets');Reject=$true},
        @{Log='WARN (EX3988) : ROM problem';Reject=$true},
        @{Log='WARN (EX3791) : width problem';Reject=$true},
        @{Log='WARN (EX3073) : port problem';Reject=$true},
        @{Log='WARN (TA2003) : ignored constraint';Reject=$true},
        @{Log='WARN (AG0101) : The netlist is not one directed acyclic graph';Reject=$true},
        @{Log='WARN (PR1014) : clock access requires review';Reject=$false}
    )
    foreach($case in $cases){
        if(($case.Log -match $buildFailurePattern) -ne $case.Reject){throw "Log classification failed: $($case.Log)"}
    }
    Write-Output "PASS Gowin log classification: $($cases.Count) cases; all prior prohibited warning codes rejected."
    return
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
& $Python (Join-Path $root "model/pack_dual16_rom.py") --check
if($LASTEXITCODE){throw "Dual-port coefficient ROM is stale or invalid"}
& $Python (Join-Path $root "model/brightness_response.py") check
if($LASTEXITCODE){throw "Brightness response coefficient table is stale or invalid"}
$out=Join-Path $root 'build/hdmi'
if(-not(Test-Path -LiteralPath $Gowin)){throw "Missing Gowin: $Gowin"}
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $PSScriptRoot
try {
    # 同一生成步骤供GUI和命令行使用，避免两份公共引脚表逐渐不一致。
    & $Gowin build.tcl prepare *> "$out/prepare.log"
    if($LASTEXITCODE){throw 'Cannot prepare combined constraints'}
    if($PrepareOnly){Write-Output 'PASS prepared piano_hdmi.gprj (no compilation)';return}
    # 与隔离PNR共用清单；解析器、ROM、原约束、生成约束均记录身份。
    & $Python "$PSScriptRoot/build_inputs.py" --root $root
    if($LASTEXITCODE){throw 'Cannot enumerate HDMI build inputs'}
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
    if($log -match $buildFailurePattern){throw 'Build has unresolved error, ROM, width, interface or constraint warning'}
    & $Python "$PSScriptRoot/build_inputs.py" --verify "$out/build_inputs.txt"
    if($LASTEXITCODE){throw 'HDMI input changed during build'}
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
