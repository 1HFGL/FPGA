[CmdletBinding()]
param(
    [string]$DestinationPath = (Join-Path $env:LOCALAPPDATA 'Programs/JingzouStudio'),
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Desktop'),
    [switch]$NoShortcuts
)
$ErrorActionPreference = 'Stop'
function Get-PackageHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}
$productId = 'org.jingzou.studio'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'app'))
$destinationRoot = [IO.Path]::GetFullPath($DestinationPath).TrimEnd('\')
$sourcePrefix = $sourceRoot.TrimEnd('\') + '\'
$destinationPrefix = $destinationRoot + '\'
if ($destinationRoot -eq [IO.Path]::GetPathRoot($destinationRoot).TrimEnd('\') -or
    $destinationRoot.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $destinationRoot -eq $sourceRoot) {
    throw 'Choose a separate application folder, not a drive root or this package.'
}
$manifestPath = Join-Path $PSScriptRoot 'package-files.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.application_id -ne $productId) { throw 'Unexpected package identity.' }
$markerPath = Join-Path $destinationRoot 'installed.json'
if ((Test-Path -LiteralPath $destinationRoot) -and
    @(Get-ChildItem -LiteralPath $destinationRoot -Force).Count -gt 0) {
    if (-not (Test-Path -LiteralPath $markerPath)) { throw 'The destination is not an existing Jingzou installation.' }
    $previous = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($previous.application_id -ne $productId) { throw 'Refusing to overwrite another application.' }
}
# Check every byte and every resolved path before making installation changes.
foreach ($entry in $manifest.files.PSObject.Properties) {
    $relative = $entry.Name
    if ([IO.Path]::IsPathRooted($relative)) { throw 'Invalid absolute package path.' }
    $sourceFile = [IO.Path]::GetFullPath((Join-Path $sourceRoot $relative))
    $destinationFile = [IO.Path]::GetFullPath((Join-Path $destinationRoot $relative))
    if (-not $sourceFile.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $destinationFile.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'A package path escapes its application folder.'
    }
    if ((Get-PackageHash $sourceFile) -ne $entry.Value) {
        throw "Package integrity failure: $relative"
    }
}
New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
$plannedFiles = @($manifest.files.PSObject.Properties.Name) + @('Uninstall.ps1', 'Uninstall.cmd')
# Retain a recoverable identity if copying or shortcut creation is interrupted.
@{ application_id=$productId; version=$manifest.version; files=$plannedFiles; shortcuts=@() } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerPath -Encoding UTF8
$managed = @()
foreach ($entry in $manifest.files.PSObject.Properties) {
    $destinationFile = [IO.Path]::GetFullPath((Join-Path $destinationRoot $entry.Name))
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationFile) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot $entry.Name) -Destination $destinationFile -Force
    $managed += $entry.Name
}
foreach ($name in @('Uninstall.ps1', 'Uninstall.cmd')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $destinationRoot $name) -Force
    $managed += $name
}
$shortcuts = @()
if (-not $NoShortcuts) {
    New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    foreach ($item in @(@('声场上位机', ''), @('声场上位机（测试模式）', '--demo'))) {
        $linkPath = Join-Path $ShortcutDirectory ($item[0] + '.lnk')
        if (Test-Path -LiteralPath $linkPath) {
            $existing = $shell.CreateShortcut($linkPath)
            if ($existing.TargetPath -ne (Join-Path $destinationRoot 'JingzouStudio.exe')) {
                throw "A shortcut with this name already belongs to another location: $linkPath"
            }
        }
        $link = $shell.CreateShortcut($linkPath)
        $link.TargetPath = Join-Path $destinationRoot 'JingzouStudio.exe'
        $link.WorkingDirectory = $destinationRoot
        $link.Arguments = $item[1]
        $link.IconLocation = $link.TargetPath + ',0'
        $link.Save()
        $shortcuts += $linkPath
    }
}
@{ application_id=$productId; version=$manifest.version; files=$managed; shortcuts=$shortcuts } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerPath -Encoding UTF8
Write-Output "Installed: $destinationRoot"
Write-Output 'Test mode is silent and never opens a physical COM port.'
