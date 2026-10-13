[CmdletBinding()]
param(
    [string]$ModelSimBin='C:/Library/modelsim/win64',
    [string]$OutputDirectory='build/b-review-20261013/latency',
    [int[]]$LeadModes=@(0,2),
    [string[]]$ExtraTests=@(),
    [switch]$NegativeControl
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($tool in @('vlib.exe','vlog.exe','vsim.exe')) {
    if(-not(Test-Path -LiteralPath (Join-Path $ModelSimBin $tool))) {throw "Missing simulator tool: $ModelSimBin/$tool"}
}
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $out.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must be a repository subdirectory.'
}
New-Item -ItemType Directory -Path $out -Force | Out-Null
$relativeOut=$out.Substring($root.Length+1).Replace('\','/')
$tag=if($NegativeControl){'negative'}else{'normal'}
$lib="$relativeOut/${tag}_work"

# 穷举3125个系统时钟相位，不把14个有向工况的观测最大值冒充全相位证明。
# 此模型只算调度/串行化，不模拟机械接点、亚稳态和模拟输出。
function Get-PhaseBounds([int]$lead,[int]$contentSamples) {
    $requests=[Collections.Generic.List[int]]::new()
    $frames=[Collections.Generic.List[int]]::new()
    $rights=[Collections.Generic.List[int]]::new()
    $lefts=[Collections.Generic.List[int]]::new()
    [long]$acc=0; $edge=0
    for($cycle=0;$cycle -lt 125000;$cycle++) {
        $acc+=3072000
        if($acc -ge 50000000) {
            $acc-=50000000
            if($edge -eq 0){$frames.Add($cycle)}
            if($edge -eq 31){$rights.Add($cycle)}
            if($edge -eq 63){$lefts.Add($cycle)}
            if($edge -eq $(if($lead -eq 0){0}else{64-$lead})){$requests.Add($cycle)}
            $edge=($edge+1)%64
        }
    }
    $rows=foreach($phase in 0..3124) {
        # 同步2拍、100000拍消抖、press/pending/FIFO、握手/4槽扫描/APPLY，
        # 从最后稳定输入到可被A采样的gate按100012拍保守计。
        # 不能漏掉稳定边沿刚过时钟沿时不足一拍的异步等待；取整到下一拍。
        $arrival=5000+$phase
        $eligible=$arrival+100012
        $ri=0
        while($requests[$ri] -lt $eligible){$ri++}
        $request=$requests[$ri+$contentSamples-1]
        $fi=0
        # 同一沿valid属于下一缓存；必须在R4之后才允许帧消费。
        while($frames[$fi] -le $request+4){$fi++}
        [pscustomobject]@{
            phase=$phase;lead=$lead;content_samples=$contentSamples
            request_cycles=$request-$arrival;pcm_cycles=$request+3-$arrival
            cache_cycles=$request+4-$arrival;right_cycles=$rights[$fi]-$arrival
            left_cycles=$lefts[$fi]-$arrival
        }
    }
    $rows | Export-Csv -LiteralPath "$out/phase_lead${lead}_samples${contentSamples}.csv" -NoTypeInformation -Encoding utf8
    [pscustomobject]@{
        lead=$lead; phases=3125; content_samples=$contentSamples
        max_left_cycles=($rows | Measure-Object left_cycles -Maximum).Maximum
        max_left_ns=20*($rows | Measure-Object left_cycles -Maximum).Maximum
        min_left_ns=20*($rows | Measure-Object left_cycles -Minimum).Minimum
        worst_phases=@($rows | Where-Object left_cycles -eq ($rows | Measure-Object left_cycles -Maximum).Maximum | Select-Object -ExpandProperty phase)
    }
}

# 固定C4新空闲声部的音量界：枚举所有32位初相位的等价查表区间，
# 不只枚举1024个地址的中心。每一步查表变界点都纳入低22位分区。
# 原96点起音、velocity=100、MIX_SHIFT=5；abs(声部样本)>=32时，
# 无削波背景与新增音的混音差至少1LSB（本4路/32缩放不会削波）。
function Get-FreshC4ResponseBound {
    $rom=@(Get-Content -LiteralPath (Join-Path $root 'rtl/rom/piano_1024.mem') |
        Where-Object {$_ -match '^[0-9A-Fa-f]{4}$'} |
        ForEach-Object {$value=[Convert]::ToInt32($_,16);if($value -ge 32768){$value-65536}else{$value}})
    if($rom.Count -ne 1024){throw 'Expected exactly 1024 piano ROM words'}
    $noteLut=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl') -Recurse -Filter 'note_phase_lut.v')
    if($noteLut.Count -ne 1){throw 'Expected exactly one active note_phase_lut.v'}
    $noteBody=Get-Content -LiteralPath $noteLut[0].FullName -Raw
    if($noteBody -notmatch "7'd60:\s*phase_inc\s*=\s*32'd(\d+)") {throw 'Cannot read C4 phase increment'}
    [long]$inc=$Matches[1]; [long]$cell=4194304; $maxSamples=16
    $cuts=@(0)+@(for($k=0;$k -lt $maxSamples;$k++){($cell-(($k*$inc)%$cell))%$cell})
    $cuts=@($cuts | Sort-Object -Unique)
    $worst=0; $states=0
    for($address=0;$address -lt 1024;$address++) {
        foreach($fraction in $cuts) {
            $first=0
            for($k=1;$k -le $maxSamples;$k++) {
                [long]$phase=($address*$cell+$fraction+($k-1)*$inc)%4294967296
                $raw=$rom[[int][Math]::Floor($phase/$cell)]
                $env=[Math]::Floor(65536.0*$k/96)
                $gain=[Math]::Floor([Math]::Floor($raw*$env/65536.0)*100/128.0)
                if([Math]::Abs($gain) -ge 32){$first=$k;break}
            }
            if($first -eq 0){throw "C4 threshold not bounded within $maxSamples samples at address=$address fraction=$fraction"}
            if($first -gt $worst){$worst=$first}
            $states++
        }
    }
    [pscustomobject]@{max_samples=$worst;equivalent_phase_intervals=$states;
        scope='Fresh C4 voice, velocity100, attack96, any initial DDS phase, unchanged unclipped background. Not arbitrary stealing/retrigger/cancel response.'}
}

Push-Location $root
try {
    $sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl') -Filter '*.v' -Recurse | Sort-Object FullName | ForEach-Object {$_.FullName})
    $sources+=Join-Path $PSScriptRoot 'tb_piano_latency.v'
    foreach($test in $ExtraTests){
        $path=Join-Path $PSScriptRoot "$test.v"
        if(-not(Test-Path -LiteralPath $path)){throw "Missing extra test: $path"}
        $sources+=$path
    }
    $manifest=@("UTC=$([DateTime]::UtcNow.ToString('o'))","GitHEAD=$(git rev-parse HEAD)",
        "ModelSim=$(& "$ModelSimBin/vsim.exe" -version)",
        'Flags=-vlog01compat -pedanticerrors',"LeadModes=$($LeadModes -join ',')",'Threshold=1 integer LSB; digital only')
    foreach($file in ($sources+@('rtl/rom/piano_1024.mem',$PSCommandPath))){
        $manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"
    }
    $manifest | Set-Content -LiteralPath "$out/${tag}_inputs.txt" -Encoding utf8
    if($NegativeControl){
        # 只变更build副本：让串行输出反相。原检查器必须拒绝，脚本也必须非零。
        $original=Join-Path $root 'rtl/i2s_tx.v'
        if(-not(Test-Path -LiteralPath $original)){$original=Join-Path $root 'rtl/audio/i2s_tx.v'}
        $body=Get-Content -LiteralPath $original -Raw
        $changed=$body.Replace('i2s_sdata <= shift_reg[SAMPLE_BITS-2];','i2s_sdata <= ~shift_reg[SAMPLE_BITS-2];')
        if($changed -eq $body){throw 'Negative-control anchor not found; no mutation executed'}
        $copy=Join-Path $out 'mutated_i2s_tx.v'
        [IO.File]::WriteAllText($copy,$changed,[Text.UTF8Encoding]::new($false))
        $sources=@($sources | Where-Object {$_ -ne $original})+@($copy)
        "MUTATION=$((Get-FileHash -LiteralPath $copy).Hash) $copy" | Add-Content -LiteralPath "$out/${tag}_inputs.txt"
    }
    & "$ModelSimBin/vlib.exe" $lib *> "$out/${tag}_vlib.log"
    if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/${tag}_compile.log"
    if($LASTEXITCODE -ne 0){throw "Strict compilation failed: $out/${tag}_compile.log"}
    foreach($lead in $LeadModes){
        if($lead -ne 0 -and $lead -ne 2){throw 'This comparison supports only the reviewed modes 0 and 2'}
        $log="$out/tb_piano_latency_lead${lead}_${tag}.log"
        $csvPath="$relativeOut/latency_lead${lead}_${tag}.csv"
        $command=@('-c','-lib',$lib,'-l',$log,'-wlf',"$out/lead${lead}_${tag}.wlf",'tb_piano_latency',
            "-gREQUEST_LEAD_HALF_EDGES=$lead","+CSV=$csvPath",'-do',
            'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f')
        ($command -join ' ') | Set-Content -LiteralPath "$out/lead${lead}_${tag}_command.txt" -Encoding utf8
        & "$ModelSimBin/vsim.exe" @command
        $code=$LASTEXITCODE;$body=Get-Content -LiteralPath $log -Raw
        if($code -ne 0 -or $body -match '\*\* (Fatal|Error):|\bFAIL\b' -or -not $body.Contains('PASS tb_piano_latency')){
            throw "tb_piano_latency lead=$lead failed (exit=$code): $log"
        }
        if($NegativeControl){throw 'Invalid negative control: mutated RTL unexpectedly passed'}
        Write-Output "VERIFIED tb_piano_latency lead=$lead"
    }
    foreach($test in $ExtraTests){
        $log="$out/${test}.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/${test}.wlf" $test -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f'
        $code=$LASTEXITCODE;$body=Get-Content -LiteralPath $log -Raw
        if($code -ne 0 -or $body -match '\*\* (Fatal|Error):|\bFAIL\b' -or -not $body.Contains("PASS $test")){throw "$test failed: $log"}
    }
    $content=Get-FreshC4ResponseBound
    $bounds=@(foreach($lead in $LeadModes){Get-PhaseBounds $lead 1;Get-PhaseBounds $lead $content.max_samples})
    $observations=@(foreach($lead in $LeadModes){
        $rows=@(Import-Csv -LiteralPath "$out/latency_lead${lead}_${tag}.csv")
        if($rows.Count -ne 14){throw "Missing directed latency cases for lead=$lead"}
        $freshBound=@($bounds | Where-Object {$_.lead -eq $lead -and $_.content_samples -eq $content.max_samples})[0]
        foreach($row in @($rows | Where-Object {$_.name -like 'first_*' -or $_.name -eq 'background_new_note'})) {
            if(([long]$row.left_ns-[long]$row.raw_ns) -gt $freshBound.max_left_ns -or
                [int]$row.samples_to_difference -gt $content.max_samples) {
                throw "Fresh-note observation exceeds derived bound: lead=$lead case=$($row.name)"
            }
        }
        $latencies=@($rows | ForEach-Object {[long]$_.left_ns-[long]$_.raw_ns})
        [pscustomobject]@{lead=$lead;cases=$rows.Count;min_left_ns=($latencies | Measure-Object -Minimum).Minimum;
            max_left_ns=($latencies | Measure-Object -Maximum).Maximum;
            max_samples_to_difference=($rows | Measure-Object samples_to_difference -Maximum).Maximum}
    })
    if($LeadModes -contains 0 -and $LeadModes -contains 2) {
        $old=@($observations | Where-Object lead -eq 0)[0]
        $new=@($observations | Where-Object lead -eq 2)[0]
        if($new.max_left_ns -ge $old.max_left_ns){throw 'Early-request mode failed to reduce observed maximum latency'}
    }
    [pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');observed=$observations;
        phase_bounds=$bounds;fresh_c4_content_bound=$content;
        assumptions=@('50MHz/48kHz exact nominal clocks; stable raw edge; no analog metastability model',
        '100000-cycle debounce; control bound100012 cycles includes ceil asynchronous phase, assumes empty event queues/no simultaneous cancel',
        'Scheduling bound is first eligible requested sample, not necessarily nonzero',
        'Fresh C4 content bound covers any DDS phase and unchanged background, not stealing/retrigger/cancel',
        'Busy/steal/retrigger/single PANIC are directed measured cases, not exhaustive arbitrary input streams',
        'Real DAC/PA/headphones, arbitrary mechanical bounce, and 13-key future integration are not measured')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$out/latency_summary.json" -Encoding utf8
    Write-Output "PASS latency comparison; measured cases and conditional 3125-phase bounds: $out/latency_summary.json"
} finally {Pop-Location}
