[CmdletBinding()]
param([string]$ModelSimBin='C:\Library\modelsim\win64',
      [string]$OutputDirectory='results/display-20261013', [switch]$NegativeControl)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    foreach($tool in @('vlib','vlog','vsim')) {
        if(-not(Test-Path "$ModelSimBin/$tool.exe")){throw "Missing $tool"}
    }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $tag=if($NegativeControl){'negative'}else{'normal'}
    $lib="$OutputDirectory/${tag}_work"
    if(-not(Test-Path "$lib/_info")) {
        & "$ModelSimBin/vlib.exe" $lib
        if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    }
    $sources=@('rtl/display_cdc_latest.v','rtl/lcd_rgb_timing.v','rtl/display_wave_buffer.v',
        'rtl/display_font24.v','rtl/piano_display_renderer.v','rtl/instrument_display.v',
        'sim/tb_display_timing.v','sim/tb_display_cdc.v','sim/tb_display_wave.v',
        'sim/tb_display_renderer.v','sim/tb_display_reset_gain.v','sim/tb_instrument_display.v')
    # 可重复负向对照只改生成目录中的副本，故意缩短一拍HSYNC；原RTL/队友tb均不动。
    if($NegativeControl) {
        $original=Get-Content 'rtl/lcd_rgb_timing.v' -Raw
        $needle='x<H_ACTIVE+H_FRONT+H_SYNC)'
        if(-not $original.Contains($needle)){throw 'Mutation target changed'}
        $mutated=$original.Replace($needle,'x<H_ACTIVE+H_FRONT+H_SYNC-1)')
        $mutation="$OutputDirectory/timing_mutation.v"
        $mutated | Set-Content $mutation -Encoding utf8
        $sources=@($sources | ForEach-Object {if($_ -eq 'rtl/lcd_rgb_timing.v'){$mutation}else{$_}})
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)", 'flags=-vlog01compat -pedanticerrors')
    foreach($source in ($sources+@($PSCommandPath))) {
        $manifest+="$((Get-FileHash -LiteralPath $source).Hash)  $source"
    }
    $manifest | Set-Content "$OutputDirectory/${tag}_inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$OutputDirectory/${tag}_compile.log"
    if($LASTEXITCODE -ne 0){throw "Compile failed: $OutputDirectory/${tag}_compile.log"}
    $tests=if($NegativeControl){@('tb_display_timing')}else{
        @('tb_display_timing','tb_display_cdc','tb_display_wave','tb_display_renderer','tb_display_reset_gain','tb_instrument_display')}
    foreach($top in $tests) {
        $log="$OutputDirectory/${top}_${tag}.log"
        $extra=@()
        if($top -eq 'tb_instrument_display'){
            $extra=@("+PIANO_FRAME=$OutputDirectory/piano_frame.hex","+GUITAR_FRAME=$OutputDirectory/guitar_frame.hex")
        }
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$OutputDirectory/${top}_${tag}.wlf" $top @extra -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$OutputDirectory/${top}_${tag}_console.log"
        $exitCode=$LASTEXITCODE
        $body=Get-Content -LiteralPath $log -Raw
        if($NegativeControl) {
            if($body -notmatch 'FAIL timing expected' -or $body.Contains("PASS $top")){throw 'Mutation not rejected by expected checker'}
            Write-Output 'PASS negative control: shortened HSYNC rejected by timing scoreboard.'
        } else {
            if($exitCode -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or -not $body.Contains("PASS $top")) {
                throw "Failed $top : $log"
            }
            Write-Output "PASS $top"
        }
    }
} finally {Pop-Location}
