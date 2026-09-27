[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('compile', 'run')]
    [string]$Mode = 'run',
    [string]$Top = 'dds_sine_tb',
    [string[]]$Sources = @('rtl/dds_sine.v', 'sim/dds_sine_tb.v'),
    [string]$WorkLibrary = 'work'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modelsimRoot = 'C:\Library\modelsim\win64'
$vlib = Join-Path $modelsimRoot 'vlib.exe'
$vlog = Join-Path $modelsimRoot 'vlog.exe'
$vsim = Join-Path $modelsimRoot 'vsim.exe'
$simulationRoot = Join-Path $projectRoot 'sim'
$sourceList = @(
    foreach ($source in $Sources) {
        $source -split '[,;]' | ForEach-Object {
            $trimmed = $_.Trim()
            if ($trimmed) { $trimmed }
        }
    }
)

if ($sourceList.Count -eq 0) {
    throw 'No Verilog source files were provided.'
}

foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (!(Test-Path -LiteralPath $tool)) {
        throw "ModelSim tool not found: $tool"
    }
}

Push-Location $simulationRoot
try {
    $sourcePaths = foreach ($source in $sourceList) {
        $sourcePath = Join-Path $projectRoot $source
        if (!(Test-Path -LiteralPath $sourcePath)) {
            throw "Verilog source file not found: $sourcePath"
        }
        (Resolve-Path -LiteralPath $sourcePath).Path
    }

    if (!(Test-Path -LiteralPath (Join-Path $WorkLibrary '_info'))) {
        & $vlib $WorkLibrary
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create ModelSim work library: $WorkLibrary"
        }
    }

    Write-Host "Compiling: $($sourceList -join ', ')"
    & $vlog '-nologo' '-work' $WorkLibrary @sourcePaths
    if ($LASTEXITCODE -ne 0) {
        throw 'Verilog compilation failed. Simulation stopped.'
    }

    if ($Mode -eq 'compile') {
        Write-Host 'Compilation completed.'
        return
    }

    $resultsDirectory = Join-Path $projectRoot 'results\waves'
    New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null
    $waveFile = Join-Path $resultsDirectory "$Top.wlf"
    $doCommands = "add wave -r sim:/$Top/*; run -all"

    Write-Host "Starting simulation top: $Top"
    & $vsim '-gui' '-voptargs=+acc' '-wlf' $waveFile "$WorkLibrary.$Top" '-do' $doCommands
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to start ModelSim simulation.'
    }
}
finally {
    Pop-Location
}
