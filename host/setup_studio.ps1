$ErrorActionPreference = 'Stop'
$studioRoot = Split-Path -Parent $PSScriptRoot
$studioEnvironment = Join-Path $studioRoot '.venv-studio'
$studioPython = Join-Path $studioEnvironment 'Scripts/python.exe'
if (-not (Test-Path -LiteralPath $studioPython)) {
    $studioCandidates = @()
    $studioSystemPython = Get-Command python -ErrorAction SilentlyContinue
    if ($studioSystemPython) { $studioCandidates += $studioSystemPython.Source }
    $studioCandidates += Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    $studioBasePython = $null
    foreach ($studioCandidate in $studioCandidates) {
        if (Test-Path -LiteralPath $studioCandidate) {
            & $studioCandidate -c 'import sys; assert sys.version_info >= (3, 10)' 2>$null
            if ($LASTEXITCODE -eq 0) { $studioBasePython = $studioCandidate; break }
        }
    }
    if (-not $studioBasePython) { throw 'Python 3.10 or newer is required. Install Python and retry.' }
    & $studioBasePython -m venv $studioEnvironment
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the studio environment.' }
}
& $studioPython -m pip install --index-url https://pypi.org/simple -r (Join-Path $PSScriptRoot 'studio_requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed. Check the network and retry.' }
Write-Output 'Ready. Double-click run_tone_studio.bat.'
