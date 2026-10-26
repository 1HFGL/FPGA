[CmdletBinding()]
param([string]$Python='C:/Users/YUAN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$ownedPath=[IO.Path]::GetFullPath((Join-Path $taskRoot 'build/timing_followup_20261025'))
$expectedPath='D:\Project\fpga_contest\build\timing_followup_20261025'
if(-not $ownedPath.Equals($expectedPath,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected cleanup target'}
if(-not $ownedPath.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Target escapes project'}
& $Python (Join-Path $PSScriptRoot 'verify_archive.py')
if($LASTEXITCODE){throw 'Archive/source verification failed; refusing cleanup'}
if(Test-Path -LiteralPath $ownedPath){
    $resolved=(Resolve-Path -LiteralPath $ownedPath).Path
    if(-not $resolved.Equals($expectedPath,[StringComparison]::OrdinalIgnoreCase)){throw 'Resolved target differs'}
    $links=@(Get-ChildItem -LiteralPath $ownedPath -Recurse -Force -Attributes ReparsePoint)
    if($links.Count){throw 'Reparse points found; refusing recursive cleanup'}
    Remove-Item -LiteralPath $ownedPath -Recurse -Force
}
& $Python (Join-Path $PSScriptRoot 'verify_archive.py') --after-cleanup
if($LASTEXITCODE){throw 'Post-cleanup verification failed'}
Write-Output 'PASS removed only the verified owned candidates and temporary backup'
