[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$OutputPath = 'build/repository-migration/manifest.json',
    [string]$VerifyManifest = '',
    [ValidateSet('Source', 'Destination')][string]$VerifySide = 'Source',
    [switch]$ImmutableOnly
)
# 只生成/核对逐文件清单，绝不移动或删除文件。迁移执行者必须先重新跑 Source 核对。
# ignored 文件不等于垃圾：队友快照全部保留，未知输出只拟隔离，位流和配置不得删除。
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate repository root.' }
}
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
if (!(Test-Path -LiteralPath (Join-Path $root '.git'))) { throw "Not a Git workspace: $root" }

function Get-LocalPath([string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '[\x00-\x1f]' -or
        [IO.Path]::IsPathRooted($Relative)) { throw "Expected safe relative path: $Relative" }
    $full = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (!$full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes workspace or targets its root: $Relative"
    }
    $normalized = $full.Substring($rootPrefix.Length).Replace('\', '/')
    if ($normalized -ne $Relative.Replace('\', '/').TrimEnd('/')) {
        throw "Non-canonical relative path (dot segments or aliases): $Relative"
    }
    if ($normalized -match '(^|/)(\.git|\.venv[^/]*|venv|node_modules)(/|$)') {
        throw "Protected environment path: $Relative"
    }
    # 不跟随 junction/symlink：字符串前缀本身不能证明实际落点在工作区内。
    $ancestor = $full
    while ($ancestor -ne $root) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point requires manual handling: $ancestor"
            }
        }
        $ancestor = Split-Path -Parent $ancestor
    }
    return $full
}

function Get-RelativePath([string]$Absolute) {
    $full = [IO.Path]::GetFullPath($Absolute)
    if (!$full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside repository: $Absolute"
    }
    return $full.Substring($rootPrefix.Length).Replace('\', '/')
}

function Read-GitFiles([string[]]$Options) {
    $lines = @(& git -C $root -c core.quotepath=false ls-files @Options)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
    foreach ($line in $lines) {
        if ($line -match '[\x00-\x1f]' -or $line.StartsWith('"')) {
            throw "Unusual file name requires manual handling: $line"
        }
        if ($line) { $line.Replace('\', '/') }
    }
}

function Get-StableHash([string]$Absolute) {
    $before = Get-Item -LiteralPath $Absolute -Force
    $hash = (Get-FileHash -LiteralPath $Absolute -Algorithm SHA256).Hash
    $after = Get-Item -LiteralPath $Absolute -Force
    if ($before.Length -ne $after.Length -or $before.LastWriteTimeUtc -ne $after.LastWriteTimeUtc) {
        throw "File changed during inventory; rerun after writer stops: $Absolute"
    }
    return $hash
}

function Get-InventoryFiles {
    $tracked = @{}
    foreach ($name in @(Read-GitFiles @('--cached'))) { $tracked[$name] = $true }
    $visible = @{}
    foreach ($name in @(Read-GitFiles @('--cached', '--others', '--exclude-standard'))) { $visible[$name] = $true }
    $all = @{}
    foreach ($name in $visible.Keys) {
        if ($name -notmatch '^(build|\.git|\.venv[^/]*|venv|node_modules)/') { $all[$name] = $true }
    }
    # 额外遍历拟迁移目录中的 ignored 项；不遍历整个磁盘或虚拟环境。
    $scanRoots = @('rtl', 'sim', 'scripts', 'tb', 'fpga_project', 'fpga_music_tool', 'doc', 'results',
        'work', 'fpga_a', 'fpga_b', 'fpga_interaction', 'fpga_ab_sim')
    foreach ($scanRoot in $scanRoots) {
        $absolute = Get-LocalPath $scanRoot
        if (Test-Path -LiteralPath $absolute -PathType Container) {
            foreach ($item in @(Get-ChildItem -LiteralPath $absolute -Recurse -Force)) {
                $relative = Get-RelativePath $item.FullName
                $null = Get-LocalPath $relative
                if (!$item.PSIsContainer) { $all[$relative] = $true }
            }
        }
    }
    return @{ tracked = $tracked; visible = $visible; all = $all }
}

if ($VerifyManifest) {
    $manifestPath = Get-LocalPath $VerifyManifest
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw 'Unsupported manifest schema.' }
    if ($VerifySide -eq 'Source') {
        $current = Get-InventoryFiles
        $difference = @(Compare-Object @($manifest.files.source | Sort-Object) @($current.all.Keys | Sort-Object))
        if ($difference.Count -ne 0) { throw "Source file-set changed since inventory; regenerate manifest. $($difference | Out-String)" }
    }
    $seenTargets = @{}
    $verified = 0
    foreach ($entry in $manifest.files) {
        $null = Get-LocalPath $entry.source
        $null = Get-LocalPath $entry.destination
        if ($seenTargets.ContainsKey($entry.destination)) { throw "Duplicate destination: $($entry.destination)" }
        $seenTargets[$entry.destination] = $true
        if ($ImmutableOnly -and !$entry.preserveBytes) { continue }
        $relative = if ($VerifySide -eq 'Source') { $entry.source } else { $entry.destination }
        $absolute = Get-LocalPath $relative
        if (!(Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Missing file: $relative" }
        if ((Get-StableHash $absolute) -ne $entry.sha256) { throw "SHA256 mismatch: $relative" }
        $verified++
    }
    # 对四个快照同时检查路径集合；只比已知 hash 会漏掉新增/遗失文件。
    foreach ($snapshot in @('fpga_a', 'fpga_b', 'fpga_interaction', 'fpga_ab_sim')) {
        $prefix = if ($VerifySide -eq 'Source') { "$snapshot/" } else { "upstream/$snapshot/" }
        $expected = @($manifest.files | Where-Object { $_.source.StartsWith("$snapshot/") } |
            ForEach-Object { if ($VerifySide -eq 'Source') { $_.source } else { $_.destination } } | Sort-Object)
        $actual = @(Get-ChildItem -LiteralPath (Get-LocalPath $prefix.TrimEnd('/')) -Force -Recurse -File |
            ForEach-Object { Get-RelativePath $_.FullName } | Sort-Object)
        if (@(Compare-Object $expected $actual).Count -ne 0) { throw "Snapshot path-set mismatch: $snapshot" }
    }
    Write-Host "PASS: $verified $VerifySide hashes verified; four snapshot file sets unchanged."
    exit 0
}

$inventory = Get-InventoryFiles
$tracked = $inventory.tracked
$visible = $inventory.visible
$all = $inventory.all

$rtlGroups = @{
    audio = @('sample_tick', 'i2s_tx', 'synth_top')
    display = @('display_cdc_latest', 'display_font24', 'display_wave_buffer', 'instrument_display',
        'lcd_rgb_timing', 'piano_display_renderer')
    common = @('reset_sync')
    control = @('event_encoder', 'input_sync_debounce', 'pressure_if', 'touch_or_key_if', 'voice_allocator',
        'voice_test_pattern', 'note_phase_lut', 'interaction_top', 'uart_event_arbiter', 'uart_fifo',
        'uart_line_rx', 'uart_reply_tx', 'uart_rx', 'uart_synth_protocol', 'uart_tx')
    top = @('board_test_top', 'board_top', 'instrument_adsr_top', 'instrument_demo_top',
        'instrument_presets_top', 'instrument_uart_piano_top', 'instrument_uart_top', 'single_tone_demo_top')
    synth = @('adsr_env', 'adsr_voice_bank', 'demo_voice_bank', 'instrument_env', 'instrument_wave',
        'phase_acc', 'sample_gain', 'sample_mixer4', 'voice_adsr', 'voice_bank_adsr', 'voice_bank_instruments',
        'voice_dds', 'voice_instrument', 'voice_timbre_adsr', 'wave_lut', 'wave_lut_timbre')
}
$entries = [Collections.Generic.List[object]]::new()
$targetOwners = @{}
foreach ($source in @($all.Keys | Sort-Object)) {
    $absolute = Get-LocalPath $source
    if (!(Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Missing indexed file: $source" }
    $destination = $source
    $category = 'unchanged'
    $reason = '不在本次移动范围；记录当前字节，保留原位。'
    $preserveBytes = $false
    $ignored = !$visible.ContainsKey($source)
    $leaf = [IO.Path]::GetFileName($source)
    if ($source -match '^(fpga_a|fpga_b|fpga_interaction|fpga_ab_sim)/') {
        $destination = "upstream/$source"; $category = 'upstream-snapshot'; $preserveBytes = $true
        $reason = '四个兄弟快照整体迁移，含忽略文件；内部路径集合和每个字节必须不变。'
    } elseif ($source -match '^results/(.+)$') {
        if ($tracked.ContainsKey($source)) {
            $destination = "docs/reports/legacy/$($Matches[1])"; $category = 'historical-evidence'; $preserveBytes = $true
            $reason = '已提交历史证据原样归档，不改原报告、哈希、日期或旧绝对路径。'
        } else {
            $destination = "build/retained-before-migration/$source"; $category = 'retained-output'; $preserveBytes = $true
            $reason = '未提交输出先保全到 build；尚未判断冗余或运行状态，不能据此删除。'
        }
    } elseif ($source -match '^doc/(.+)$') {
        $destination = "docs/history/legacy-doc/$($Matches[1])"; $category = 'historical-document'; $preserveBytes = $true
        $reason = '历史原文原样保留，以索引说明新位置。'
    } elseif ($source -match '^rtl/([^/]+)\.v$') {
        $module = $Matches[1]
        $groups = @($rtlGroups.Keys | Where-Object { $rtlGroups[$_] -contains $module })
        if ($groups.Count -ne 1) { throw "RTL ownership needs explicit mapping: $source" }
        $destination = "rtl/$($groups[0])/$leaf"; $category = "rtl-$($groups[0])"
        $reason = '按经审阅的模块职责分组；此清单不更改模块名、接口或逻辑。'
    } elseif ($source -match '^(sim|tb)/[^/]+\.v$') {
        $group = if ($leaf -match '^tb_(audio_display_isolation|piano_latency)\.v$') { 'integration' }
            elseif ($leaf -match 'display') { 'display' }
            elseif ($leaf -match '^(sample_tick_tb|synth_top_tb|tb_audio_boundaries|tb_pa_tail)\.v$') { 'audio' }
            elseif ($leaf -match '^tb_(input_sync|event_encoder|pressure_if|voice_allocator|voice_test_pattern|allocator_|uart_(bytes|line|flow|protocol|replies))') { 'control' }
            elseif ($leaf -match '^tb_(adsr_|demo_voice_bank|phase_acc|piano_tone|sample_|timbre_|voice_|wave_|instrument_(wave|bank|preview))') { 'synth' }
            else { 'integration' }
        $destination = "verification/tb/$group/$leaf"; $category = "test-$group"
        $reason = '主项目 Verilog 测试按被测边界分组；未被单模块规则匹配的测试归联合测试。'
    } elseif ($source -eq 'run_modelsim.ps1') {
        $destination = 'verification/scripts/run_modelsim.ps1'; $category = 'verification-script'
        $reason = '主默认入口迁移并由后续补丁改为有效 B 测试；不与 C 包装器重名。'
    } elseif ($source -match '^(sim|scripts)/[^/]+\.(ps1|bat|tcl|do|py)$') {
        if ($source -match '^scripts/run_modelsim\.(ps1|bat)$') { $leaf = "run_c_modelsim.$($Matches[1])" }
        $destination = "verification/scripts/$leaf"; $category = 'verification-script'
        $reason = '验证/生成脚本统一入口；后续修复仓库根层级及源文件路径，不依赖调用目录。'
    } elseif ($source -match '^fpga_music_tool/(.+)$') {
        $destination = "host/$($Matches[1])"; $category = 'host-tool'
        $reason = '上位机含预设/测试全部保留；既有根目录虚拟环境不移动不重装。'
    } elseif ($source -match '^fpga_project/(.+)$') {
        $tail = $Matches[1]
        $destination = switch -Regex ($tail) {
            '^uart_piano/(.+)$' { "projects/piano/$($Matches[1])"; break }
            '^uart_basic/(.+)$' { "projects/uart_basic/$($Matches[1])"; break }
            '^display_rgb/(.+)$' { "projects/display/$($Matches[1])"; break }
            '^instruments_board/(.+)$' { "projects/examples/instruments_board/$($Matches[1])"; break }
            '^(poly_adsr_check|instruments_check)/(.+)$' { "projects/checks/$($Matches[1])/$($Matches[2])"; break }
            '^legacy/(.+)$' { "projects/legacy/$($Matches[1])"; break }
            '^(Documents/.+|audio_clk\.sdc|src/.+)$' { "projects/legacy/$tail"; break }
            '^README\.md$' { 'projects/README.md'; break }
            default { "projects/examples/adsr/$tail" }
        }
        $category = 'eda-project'
        $reason = '保留工程及邻近 Gowin 输出；配置与源引用后续审计，不能只凭 impl 名称删除。'
        if ($leaf -match 'process_config\.json$') {
            $category = 'required-process-config'
            $reason = '必要 process 配置白名单；含 ignored 配置，须显式保全并审阅构建选项。'
            if ($tail -match '^(Documents|legacy)/') { $preserveBytes = $true }
        } elseif ($tail -match '^(Documents|legacy)/') {
            $category = 'legacy-project'; $preserveBytes = $true
            $reason = '历史或来源待核实的完整工程保全，不据此宣称已重新构建。'
        }
    } elseif ($source -match '^(work|sim/work)/' -or ($ignored -and $source -match '^(sim|tb|scripts)/')) {
        $destination = "build/retained-before-migration/$source"; $category = 'retained-output'; $preserveBytes = $true
        $reason = '旧工作库或未知忽略项仅拟保全；清理需另查生成来源及占用状态。'
    } elseif ($source -match '^(rtl/rom/|docs/(sources|history|reports)/|docs/display-font/OFL\.txt$)') {
        $preserveBytes = $true
        $reason = 'ROM、原始资料、历史证据或许可证原位保留；不批量替换内容。'
    }
    $target = Get-LocalPath $destination
    if ($targetOwners.ContainsKey($destination)) { throw "Destination collision: $source and $($targetOwners[$destination]) -> $destination" }
    $targetOwners[$destination] = $source
    if ($source -ne $destination -and (Test-Path -LiteralPath $target)) { throw "Destination already exists: $destination" }
    $item = Get-Item -LiteralPath $absolute
    $entries.Add([pscustomobject][ordered]@{
        source = $source; destination = $destination; category = $category
        action = $(if ($source -eq $destination) { 'retain' } else { 'move' })
        reason = $reason; tracked = $tracked.ContainsKey($source); ignored = $ignored
        preserveBytes = $preserveBytes; bytes = $item.Length; sha256 = (Get-StableHash $absolute)
    })
}

# 风险报告是引用审阅清单，不自动重写内容，更不改历史日志或队友快照。
$sourceMap = @{}
foreach ($entry in $entries) { $sourceMap[$entry.source] = $entry.destination }
$risks = [Collections.Generic.List[object]]::new()
foreach ($entry in $entries) {
    if ($entry.category -in @('retained-output', 'historical-evidence', 'historical-document') -or
        $entry.source -match '^docs/(reports|history|sources)/' -or
        $entry.source -match '/(impl|__pycache__)/') { continue }
    $extension = [IO.Path]::GetExtension($entry.source)
    if ($extension -notin @('.gprj', '.ps1', '.bat', '.tcl', '.do', '.py', '.v', '.md', '.json', '.sdc')) { continue }
    $lines = @(Get-Content -LiteralPath (Get-LocalPath $entry.source) -Encoding UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(fpga_project|fpga_music_tool|fpga_a|fpga_b|fpga_interaction|fpga_ab_sim|rtl|sim|tb|results|doc)[/\\]|PSScriptRoot|Split-Path|__file__|\.parents\[|file dirname|open_project|readmem[hb]|\b(cd|pushd)\s') {
            $risks.Add([pscustomobject]@{ source = $entry.source; destination = $entry.destination
                line = $i + 1; kind = 'path-or-root-review'; protected = $entry.preserveBytes
                text = $lines[$i].Trim() })
        }
    }
    if ($extension -eq '.gprj') {
        $projectText = $lines -join "`n"
        try { [xml]$project = $projectText } catch {
            # 部分历史快照的声明是 version="1"（不是合法 XML 1.0）。
            # 不修原文件；记录风险，仅在内存移除声明继续读取 File 标签。
            $risks.Add([pscustomobject]@{ source = $entry.source; destination = $entry.destination
                kind = 'gprj-xml-parse-error'; protected = $entry.preserveBytes; text = $_.Exception.Message })
            try { [xml]$project = [regex]::Replace($projectText, '^\s*<\?xml[^?]*\?>', '') }
            catch { continue }
        }
        foreach ($node in @($project.SelectNodes('//File[@path]'))) {
            $reference = [string]$node.path
            $resolved = if ([IO.Path]::IsPathRooted($reference)) { [IO.Path]::GetFullPath($reference) }
                else { [IO.Path]::GetFullPath((Join-Path (Split-Path (Get-LocalPath $entry.source) -Parent) $reference)) }
            $inside = $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
            $mapped = if ($inside) { $sourceMap[(Get-RelativePath $resolved)] } else { $null }
            $risks.Add([pscustomobject]@{ source = $entry.source; destination = $entry.destination
                kind = 'gprj-reference'; reference = $reference; currentlyExists = (Test-Path -LiteralPath $resolved -PathType Leaf)
                mappedTarget = $mapped; protected = $entry.preserveBytes })
        }
    }
}
$outputAbsolute = Get-LocalPath $OutputPath
if (!(Get-RelativePath $outputAbsolute).StartsWith('build/')) { throw 'Planner output must be under build/.' }
$manifest = [ordered]@{
    schemaVersion = 1; generatedUtc = [DateTime]::UtcNow.ToString('o'); repositoryRoot = $root
    gitHead = (& git -C $root rev-parse HEAD); plannerOnly = $true
    exclusions = @('.git', '.venv-studio', 'other virtual environments', 'node_modules', 'build',
        'ignored files outside the explicitly scanned migration roots remain in place and are not inventoried')
    policy = 'No move/delete performed. Re-run Source verification immediately before migration. preserveBytes entries must pass Destination audit.'
    summary = [ordered]@{ files = $entries.Count; moves = @($entries | Where-Object action -eq 'move').Count
        trackedHistoricalResults = @($entries | Where-Object category -eq 'historical-evidence').Count
        upstreamFiles = @($entries | Where-Object category -eq 'upstream-snapshot').Count
        processConfigs = @($entries | Where-Object category -eq 'required-process-config').Count
        referenceRisks = $risks.Count }
    files = @($entries.ToArray()); referenceRisks = @($risks.ToArray())
}
$parent = Split-Path -Parent $outputAbsolute
$null = New-Item -ItemType Directory -Path $parent -Force
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputAbsolute -Encoding UTF8
Write-Host "PASS: wrote $($entries.Count) file mappings; no files moved/deleted."
Write-Host "Historical results: $($manifest.summary.trackedHistoricalResults); upstream: $($manifest.summary.upstreamFiles); process configs: $($manifest.summary.processConfigs)."
Write-Host "Manifest / reference risks: $outputAbsolute"
