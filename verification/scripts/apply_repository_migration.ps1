[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$ManifestPath = 'build/repository-migration/manifest.json',
    [string]$LogDirectory = ''
)
# 执行前停止编辑器自动保存、仿真和 Gowin 构建，再重新生成清单。
# 此脚本只按既有清单逐文件移动；不删文件、不搬整个仓库、不改正文或 Git 索引。
# 中途失败不盲目自动回滚：JSONL 日志保留每个 intent/moved，按实存位置和 SHA256 恢复。
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate repository root.' }
}
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
if (!(Test-Path -LiteralPath (Join-Path $root '.git'))) { throw "Not a Git workspace: $root" }
if (((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Repository root is a reparse point: $root"
}

function Get-SafePath([string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '[\x00-\x1f:*?"<>|]') { throw "Expected safe relative path: $Relative" }
    $full = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (!$full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes workspace or targets its root: $Relative"
    }
    $normalized = $full.Substring($rootPrefix.Length).Replace('\', '/')
    if ($normalized -ne $Relative.Replace('\', '/') -or
        $normalized -match '(^|/)(\.git|\.venv[^/]*|venv|node_modules)(/|$)') {
        throw "Non-canonical or protected path: $Relative"
    }
    # 检查每个现有祖先，避免 junction、符号链接或文件/目录冲突绕过根目录边界。
    $ancestor = $full
    while ($ancestor -ne $root) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point requires manual handling: $ancestor"
            }
            if ($ancestor -ne $full -and !$item.PSIsContainer) { throw "Parent path is a file: $ancestor" }
        }
        $ancestor = Split-Path -Parent $ancestor
    }
    return $full
}

$manifestAbsolute = Get-SafePath $ManifestPath
$manifestHash = (Get-FileHash -LiteralPath $manifestAbsolute -Algorithm SHA256).Hash
$manifest = Get-Content -LiteralPath $manifestAbsolute -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or @($manifest.files).Count -eq 0) { throw 'Empty/unsupported migration manifest.' }
if ([IO.Path]::GetFullPath($manifest.repositoryRoot).TrimEnd('\', '/') -ne $root) {
    throw 'Manifest belongs to a different repository root; regenerate it here.'
}
$sources = @{}
$destinations = @{}
$moves = [Collections.Generic.List[object]]::new()
foreach ($entry in $manifest.files) {
    $source = Get-SafePath $entry.source
    $destination = Get-SafePath $entry.destination
    if ($sources.ContainsKey($entry.source) -or $destinations.ContainsKey($entry.destination)) {
        throw "Duplicate source/destination: $($entry.source) -> $($entry.destination)"
    }
    $sources[$entry.source] = $entry
    $destinations[$entry.destination] = $entry
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing/non-file source: $($entry.source)" }
    if ($entry.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid source hash: $($entry.source)" }
    if ($entry.action -eq 'retain') {
        if ($entry.source -ne $entry.destination) { throw "Retain entry changes path: $($entry.source)" }
    } elseif ($entry.action -eq 'move') {
        if ($entry.source -eq $entry.destination -or (Test-Path -LiteralPath $destination)) {
            throw "Move destination is identical or already exists: $($entry.destination)"
        }
        # 仅允许已批准设计中的源目录和目标目录，清单不能扩展成任意工作区搬运。
        if ($entry.source -notmatch '^(rtl|sim|scripts|tb|fpga_project|fpga_music_tool|doc|results|work|fpga_a|fpga_b|fpga_interaction|fpga_ab_sim)/' -and
            $entry.source -ne 'run_modelsim.ps1') { throw "Move source outside approved scope: $($entry.source)" }
        if ($entry.destination -notmatch '^(rtl/(audio|display|synth|control|common|top|rom)/|projects/|verification/|upstream/|host/|docs/reports/legacy/|docs/history/legacy-doc/|build/retained-before-migration/)') {
            throw "Move destination outside approved scope: $($entry.destination)"
        }
        $moves.Add($entry)
    } else { throw "Unsupported action (only retain/move allowed): $($entry.action)" }
}
# 两个尚不存在的目标也不能形成“一个是文件，另一个在该文件下面”的冲突。
foreach ($relative in $destinations.Keys) {
    $parent = Split-Path -Parent $relative
    while ($parent) {
        if ($destinations.ContainsKey($parent.Replace('\', '/'))) { throw "File/directory destination collision: $relative" }
        $parent = Split-Path -Parent $parent
    }
}
$plannerBefore = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'plan_repository_migration.ps1'))
if (!$plannerBefore.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Planner is outside workspace.' }
$plannerRelative = $plannerBefore.Substring($rootPrefix.Length).Replace('\', '/')
$plannerBefore = Get-SafePath $plannerRelative
if (!$sources.ContainsKey($plannerRelative)) { throw 'Planner itself is absent from the manifest; regenerate it.' }
$plannerAfter = Get-SafePath $sources[$plannerRelative].destination
$shell = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($shell)) { throw 'Cannot locate current PowerShell executable.' }

if (!$LogDirectory) {
    $LogDirectory = 'build/repository-migration/apply-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
}
$logAbsolute = Get-SafePath $LogDirectory
if (!$LogDirectory.Replace('\', '/').StartsWith('build/') -or (Test-Path -LiteralPath $logAbsolute)) {
    throw 'Log directory must be a new directory under build/; existing logs are never overwritten.'
}
$null = [IO.Directory]::CreateDirectory($logAbsolute)
$journalPath = Join-Path $logAbsolute 'moves.jsonl'
$snapshotPath = Join-Path $logAbsolute 'manifest.snapshot.json'
Copy-Item -LiteralPath $manifestAbsolute -Destination $snapshotPath -ErrorAction Stop
if ((Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash -ne $manifestHash -or
    (Get-FileHash -LiteralPath $manifestAbsolute -Algorithm SHA256).Hash -ne $manifestHash) {
    throw 'Manifest changed while being read; no migration performed.'
}
$snapshotRelative = $snapshotPath.Substring($rootPrefix.Length).Replace('\', '/')

function Write-Journal([string]$Event, [object]$Entry, [string]$Detail = '') {
    $record = [ordered]@{ utc = [DateTime]::UtcNow.ToString('o'); event = $Event; detail = $Detail }
    if ($null -ne $Entry) {
        $record.source = $Entry.source; $record.destination = $Entry.destination; $record.sha256 = $Entry.sha256
    }
    $record | ConvertTo-Json -Compress | Add-Content -LiteralPath $journalPath -Encoding UTF8
}

function Invoke-ManifestCheck([string]$Planner, [string]$Side) {
    # 独立进程隔离 planner 的 exit；检查退出码及明确 PASS，不能把打印 FAIL 当成功。
    $log = Join-Path $logAbsolute ($Side.ToLowerInvariant() + '-verification.log')
    & $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Planner `
        -RepositoryRoot $root -VerifyManifest $snapshotRelative -VerifySide $Side 2>&1 |
        Tee-Object -FilePath $log | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0 -or !(Select-String -LiteralPath $log -Pattern "^PASS: [0-9]+ $Side hashes verified;" -Quiet)) {
        throw "$Side manifest verification failed (exit $code); see $log"
    }
}

$moved = 0
try {
    Write-Journal 'begin' $null "manifestSHA256=$manifestHash; files=$(@($manifest.files).Count); moves=$($moves.Count)"
    Invoke-ManifestCheck $plannerBefore 'Source'
    Write-Journal 'source-verified' $null
    foreach ($entry in $moves) {
        # 临近每次移动重新复核路径、冲突与源哈希，避免长批处理期间的意外改写。
        $source = Get-SafePath $entry.source
        $destination = Get-SafePath $entry.destination
        if (!(Test-Path -LiteralPath $source -PathType Leaf) -or (Test-Path -LiteralPath $destination)) {
            throw "Source/destination changed during migration: $($entry.source)"
        }
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Source changed during migration: $($entry.source)"
        }
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        $null = Get-SafePath $entry.destination
        Write-Journal 'intent' $entry
        Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
        if ((Test-Path -LiteralPath $source) -or
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Post-move identity check failed: $($entry.destination)"
        }
        $moved++
        Write-Journal 'moved-verified' $entry
        if (($moved % 200) -eq 0) { Write-Host "Moved and verified $moved / $($moves.Count) files." }
    }
    # 必须在任何路径文本修复/重建之前核对所有目标，不仅核对 preserveBytes 项。
    Invoke-ManifestCheck $plannerAfter 'Destination'
    Write-Journal 'complete' $null "All destination hashes verified; moved=$moved; deleted=0."
    Write-Host "PASS: moved $moved files, deleted 0; all destination bytes match the manifest."
    Write-Host "Journal and source/destination verification logs: $logAbsolute"
} catch {
    Write-Journal 'failed' $null "moved-verified=$moved; $($_.Exception.Message)"
    Write-Warning "Migration stopped. Do not rerun blindly or overwrite files; inspect $journalPath and file hashes first."
    throw
}
