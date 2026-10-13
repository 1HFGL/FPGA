[CmdletBinding(PositionalBinding=$false)]
param(
    [ValidateSet('compile','run')][string]$Mode='run',
    [string]$ModelSimBin='C:/Library/modelsim/win64',
    [string]$Top='synth_top_tb',
    [string[]]$Sources=@('rtl/audio/sample_tick.v','rtl/audio/i2s_tx.v','rtl/audio/synth_top.v',
        'verification/tb/audio/synth_top_tb.v'),
    [string]$ExpectedPass='PASS synth_top_tb',
    [string]$OutputDirectory='build/regression/default-modelsim',
    [string]$WorkLibrary='',
    [switch]$Gui
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach($name in @('vlib','vlog','vsim')){
    if(-not(Test-Path -LiteralPath "$ModelSimBin/$name.exe")){throw "Missing ModelSim tool: $ModelSimBin/$name.exe"}
}
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $out.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'OutputDirectory must be within the repository'
}
New-Item -ItemType Directory -Path $out -Force | Out-Null
if(-not $WorkLibrary){$WorkLibrary=$out.Substring($root.Length+1).Replace('\','/')+'/work'}
$libPath=[IO.Path]::GetFullPath((Join-Path $root $WorkLibrary))
if(-not $libPath.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'WorkLibrary must be within the repository'
}
$lib=$libPath.Substring($root.Length+1).Replace('\','/')
$sourcePaths=@(foreach($entry in $Sources){foreach($source in ($entry -split '[,;]')){
    if($source.Trim()){
        $path=[IO.Path]::GetFullPath((Join-Path $root $source.Trim()))
        if(-not(Test-Path -LiteralPath $path)){throw "Missing Verilog source: $path"}
        if([IO.Path]::GetExtension($path) -ne '.v'){throw "Only Verilog .v sources are allowed: $path"}
        $path
    }
}})
if($sourcePaths.Count -eq 0){throw 'No Verilog sources supplied'}
if($Top -ne 'synth_top_tb' -and $ExpectedPass -eq 'PASS synth_top_tb'){
    throw 'Custom Top requires its explicit -ExpectedPass marker'
}
Push-Location $root
try{
    $manifest=@("UTC=$([DateTime]::UtcNow.ToString('o'))","GitHEAD=$(git rev-parse HEAD)",
        "ModelSim=$(& "$ModelSimBin/vsim.exe" -version)","Top=$Top Mode=$Mode Gui=$Gui",
        'flags=-vlog01compat -pedanticerrors')
    foreach($path in ($sourcePaths+@($PSCommandPath))){$manifest+="$((Get-FileHash -LiteralPath $path).Hash)  $path"}
    $manifest | Set-Content -LiteralPath "$out/inputs.txt" -Encoding utf8
    New-Item -ItemType Directory -Path (Split-Path -Parent $libPath) -Force | Out-Null
    if(-not(Test-Path -LiteralPath "$libPath/_info")){
        & "$ModelSimBin/vlib.exe" $lib *> "$out/vlib.log"
        if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    }
    & "$ModelSimBin/vlog.exe" -nologo -vlog01compat -pedanticerrors -work $lib @sourcePaths *> "$out/compile.log"
    if($LASTEXITCODE -ne 0){throw "Compilation failed: $out/compile.log"}
    if($Mode -eq 'compile'){Write-Output "PASS strict compile: $Top";return}
    if($Gui){
        # 只有显式-Gui才打开交互窗口。人工波形会话不宣称自检已经通过。
        & "$ModelSimBin/vsim.exe" -gui -lib $lib -voptargs=+acc -onfinish stop -l "$out/gui.log" -wlf "$out/gui.wlf" $Top -do "add wave -r sim:/$Top/*; run -all"
        if($LASTEXITCODE -ne 0){throw 'ModelSim GUI failed'}
        Write-Output 'GUI session finished; use the default CLI mode for automated PASS/FAIL validation.'
        return
    }
    $log="$out/run.log"
    & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/run.wlf" $Top -do 'onerror {quit -code 1 -f}; onbreak {quit -code 0 -f}; run 1 sec; quit -code 0 -f'
    $code=$LASTEXITCODE;$body=Get-Content -LiteralPath $log -Raw
    if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or -not $body.Contains($ExpectedPass)){
        throw "Simulation failed or did not complete checks: $log"
    }
    Write-Output "PASS default ModelSim self-check: $Top"
}finally{Pop-Location}
