[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',
      [string]$VendorLibrary='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v',
      [string]$OutputDirectory='build/regression/hdmi',[switch]$NegativeControl)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    foreach($tool in @('vlib','vlog','vsim')){if(-not(Test-Path "$ModelSimBin/$tool.exe")){throw "Missing $tool"}}
    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    $tag=if($NegativeControl){'negative'}else{'normal'}
    $lib="$OutputDirectory/${tag}_work"
    if(-not(Test-Path "$lib/_info")){& "$ModelSimBin/vlib.exe" $lib;if($LASTEXITCODE){throw 'vlib failed'}}
    $sources=@(Get-ChildItem rtl -Recurse -Filter '*.v' | ForEach-Object FullName)
    $sources+=@('verification/tb/display/tb_tmds_encoder.v','verification/tb/display/tb_display_hdmi_frame.v','verification/tb/display/tb_hdmi_phy.v','verification/tb/display/tb_hdmi_audio_isolation.v')
    if($NegativeControl){
        $original=Get-Content rtl/display/tmds_encoder.v -Raw
        $bad=$original.Replace("2'b01:symbol<=10'b0010101011;","2'b01:symbol<=10'b1101010100;")
        if($bad -eq $original){throw 'Mutation target missing'}
        $mutation="$OutputDirectory/tmds_mutation.v"
        $bad | Set-Content $mutation -Encoding utf8
        $sources=@($sources | ForEach-Object {if((Split-Path $_ -Leaf) -eq 'tmds_encoder.v'){$mutation}else{$_}})
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors')
    $romInputs=@(Get-ChildItem rtl/rom -Filter '*.mem' | ForEach-Object FullName)
    foreach($source in ($sources+$romInputs+@($VendorLibrary,$PSCommandPath,'verification/data/display_font_golden.mem'))){$manifest+="$((Get-FileHash -LiteralPath $source).Hash)  $source"}
    $manifest | Set-Content "$OutputDirectory/${tag}_inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$OutputDirectory/${tag}_compile.log"
    if($LASTEXITCODE){throw 'HDMI strict compilation failed'}
    # 安装版厂商原语模型单独编译，仍使用Verilog模式；不修改厂商文件。
    & "$ModelSimBin/vlog.exe" -work $lib $VendorLibrary *> "$OutputDirectory/${tag}_vendor_compile.log"
    if($LASTEXITCODE){throw 'Gowin model compilation failed'}
    $tests=if($NegativeControl){@('tb_tmds_encoder')}else{@('tb_tmds_encoder','tb_hdmi_phy','tb_display_hdmi_frame','tb_hdmi_audio_isolation')}
    foreach($top in $tests){
        $log="$OutputDirectory/${top}_${tag}.log"
        & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$OutputDirectory/${top}_${tag}.wlf" $top "+FRAME=$OutputDirectory/hdmi_frame.hex" "+GUITAR_FRAME=$OutputDirectory/hdmi_guitar_frame.hex" -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$OutputDirectory/${top}_${tag}_console.log"
        $exitCode=$LASTEXITCODE;$body=Get-Content $log -Raw
        if($NegativeControl){
            if($body -notmatch 'FAIL TMDS got=' -or $body -match 'PASS tb_'){throw 'Expected mutation failure missing'}
            Write-Output 'PASS negative control: wrong TMDS control token rejected'
        }else{
            if($exitCode -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):' -or -not $body.Contains("PASS $top")){throw "Failed $top : $log"}
            Write-Output "PASS $top"
        }
    }
} finally {Pop-Location}
