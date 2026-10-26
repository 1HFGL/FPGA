$ErrorActionPreference='Stop'
$workspace=(Resolve-Path -LiteralPath 'D:\Project\fpga_contest').Path
$expected=[IO.Path]::GetFullPath((Join-Path $workspace 'build\timing_targets_20261025'))
$target=(Resolve-Path -LiteralPath $expected).Path
if($target -ne $expected -or -not $target.StartsWith($workspace+'\build\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Unexpected cleanup path'}
$python='C:\Users\YUAN\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$verifier=Join-Path $PSScriptRoot 'verify_archive.py'
& $python $verifier
if($LASTEXITCODE -ne 0) {throw 'Archive/source verification failed; nothing removed'}
$links=@(Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
if($links.Count) {throw 'Reparse point found; cleanup refused'}
Write-Output "Verified exact cleanup target: $target"
Remove-Item -LiteralPath $target -Recurse -Force
& $python $verifier --post-cleanup
if($LASTEXITCODE -ne 0) {throw 'Cleanup completed but post-check failed; inspect preserved archive'}
