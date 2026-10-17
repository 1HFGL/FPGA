[CmdletBinding()]
param([string]$Python='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $root
try {
    $checker='verification/scripts/check_hdmi_implementation.py'
    & $Python $checker --directory build/hdmi
    if($LASTEXITCODE){throw 'Normal implementation must pass before checker fault injection'}
    $out='build/regression/hdmi_placement'
    New-Item -ItemType Directory -Force $out | Out-Null
    $inputs=@($PSCommandPath,$checker,'build/hdmi/build_inputs.txt','build/hdmi/implementation_check.json')
    $manifest=@('Generated report-only mutations; production constraints/RTL/reports remain unchanged.')
    foreach($file in $inputs){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content "$out/inputs.txt" -Encoding utf8
    foreach($case in @('placement','thin_margin')){
        $fixture="$out/$case"
        New-Item -ItemType Directory -Force $fixture | Out-Null
        foreach($file in @('build_inputs.txt','build.log','timing.txt','piano_hdmi.rpt.txt','piano_hdmi.tr','artifact.txt')){
            Copy-Item -LiteralPath "build/hdmi/$file" -Destination $fixture -Force
        }
        if($case -eq 'placement'){
            # 只伪造详细报告中的一个GRID，必须检出“约束写了但实际位置不符”。
            $path="$fixture/piano_hdmi.tr"
            $body=Get-Content -LiteralPath $path -Raw
            $bad=$body.Replace('R24C134[','R24C133[')
            $expected='Reset placement missing/moved:'
        }else{
            # 所有slack仍为正，但退回8ps不能冒充达到本轮100ps验收门槛。
            $path="$fixture/timing.txt"
            $body=Get-Content -LiteralPath $path -Raw
            $section='3.1.4 Removal Paths Table'
            $start=$body.IndexOf($section)
            if($start -lt 0){throw 'Removal table missing'}
            $head=$body.Substring(0,$start)
            $tail=$body.Substring($start)
            $pattern=[regex]::new('(?m)^(1\s+)(-?\d+\.\d+)(\s+)')
            $tail=$pattern.Replace($tail,{param($m) $m.Groups[1].Value+'0.008'+$m.Groups[3].Value},1)
            $bad=$head+$tail
            $expected='Reset optimization margin below 0.100ns: 3.1.4 Removal Paths Table'
        }
        if($bad -eq $body){throw "Mutation target missing: $case"}
        $bad | Set-Content -LiteralPath $path -Encoding utf8
        & $Python $checker --directory $fixture *> "$out/$case.log"
        $code=$LASTEXITCODE
        $log=Get-Content -LiteralPath "$out/$case.log" -Raw
        if($code -eq 0 -or -not $log.Contains($expected)){throw "Checker did not reject $case"}
        Write-Output "PASS HDMI implementation negative control: $case rejected"
    }
} finally {Pop-Location}
