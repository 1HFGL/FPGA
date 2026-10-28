$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$prefix = $root + '\'
$marker = Join-Path $root 'installed.json'
if ($root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\')) { throw 'Invalid install folder.' }
$installation = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
if ($installation.application_id -ne 'org.jingzou.studio') { throw 'Unknown application identity.' }
$files = @()
foreach ($relative in $installation.files) {
    if ([IO.Path]::IsPathRooted($relative)) { throw 'Invalid managed file path.' }
    $file = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $file.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Managed path escapes install folder.' }
    $files += $file
}
if (@($installation.shortcuts).Count -gt 0) {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcut in $installation.shortcuts) {
        if ([IO.Path]::GetExtension($shortcut) -ne '.lnk') { throw 'Invalid shortcut extension.' }
        if (Test-Path -LiteralPath $shortcut) {
            $link = $shell.CreateShortcut($shortcut)
            if ($link.TargetPath -eq (Join-Path $root 'JingzouStudio.exe')) {
                Remove-Item -LiteralPath $shortcut
            }
        }
    }
}
# No recursive deletion: only files recorded by this installation are removed.
foreach ($file in $files) {
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
Remove-Item -LiteralPath $marker
Get-ChildItem -LiteralPath $root -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object {
        if (@(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $_.FullName }
    }
if (@(Get-ChildItem -LiteralPath $root -Force).Count -eq 0) { Remove-Item -LiteralPath $root }
Write-Output 'Removed managed program files; additional user documents were retained.'
