[CmdletBinding()]
param([string]$ModelSimBin='C:/Library/modelsim/win64',
      [string]$VendorLibrary='D:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v',
      [switch]$NegativeControl)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $out='build/regression/hdmi_reset'
    New-Item -ItemType Directory -Force $out | Out-Null
    $tag=if($NegativeControl){'negative'}else{'normal'}
    $lib="$out/${tag}_work"
    foreach($tool in @('vlib','vlog','vsim')){if(-not(Test-Path "$ModelSimBin/$tool.exe")){throw "Missing $tool"}}
    if(-not(Test-Path "$lib/_info")){& "$ModelSimBin/vlib.exe" $lib;if($LASTEXITCODE){throw 'vlib failed'}}
    $sources=@(rg --files rtl -g '*.v')+@('verification/tb/review/tb_review_hdmi_reset_recovery.v')
    if($NegativeControl){
        # 故障只在首次恢复后翻转红通道，启动测试仍通过；不修改正式RTL或厂商模型。
        $target='rtl/display/dvi_tx_gowin.v'
        $source=Get-Content $target -Raw
        $needle='assign tmds_data_p=positive[2:0];assign tmds_data_n=negative[2:0];'
        if(-not $source.Contains($needle)){throw 'Reset mutation target missing'}
        $fault="integer mutation_resets=0; always @(negedge rst_n) mutation_resets=mutation_resets+1;`n"+
            "assign tmds_data_p=positive[2:0] ^ ((mutation_resets>=2)?3'b100:3'b000);`n"+
            "assign tmds_data_n=negative[2:0] ^ ((mutation_resets>=2)?3'b100:3'b000);"
        $source.Replace($needle,$fault) | Set-Content "$out/dvi_reset_mutation.v" -Encoding utf8
        $sources=@($sources | Where-Object {$_ -ne $target})+@("$out/dvi_reset_mutation.v")
    }
    $manifest=@("ModelSim=$(& "$ModelSimBin/vlog.exe" -version)",'flags=-vlog01compat -pedanticerrors')
    $inputs=$sources+@($VendorLibrary,$PSCommandPath)+@(Get-ChildItem rtl/rom -Filter '*.mem' | ForEach-Object FullName)
    foreach($file in $inputs){$manifest+="$((Get-FileHash -LiteralPath $file).Hash)  $file"}
    $manifest | Set-Content "$out/${tag}_inputs.txt" -Encoding utf8
    & "$ModelSimBin/vlog.exe" -vlog01compat -pedanticerrors -work $lib @sources *> "$out/${tag}_compile.log"
    if($LASTEXITCODE){throw 'Reset recovery strict compilation failed'}
    & "$ModelSimBin/vlog.exe" -work $lib $VendorLibrary *> "$out/${tag}_vendor_compile.log"
    if($LASTEXITCODE){throw 'Vendor model compilation failed'}
    $top='tb_review_hdmi_reset_recovery';$log="$out/${top}_${tag}.log"
    & "$ModelSimBin/vsim.exe" -c -lib $lib -l $log -wlf "$out/${top}_${tag}.wlf" $top -do 'onerror {quit -code 1 -f}; onbreak {quit -code 1 -f}; run -all; quit -code 0 -f' *> "$out/${tag}_console.log"
    $code=$LASTEXITCODE;$body=Get-Content $log -Raw
    if($NegativeControl){
        if($body -notmatch 'CASE HDMI reset recovery epoch=0 ' -or $body -notmatch 'FAIL HDMI reset word alignment epoch=1' -or $body.Contains("PASS $top")){throw 'Post-recovery lane defect not rejected'}
        Write-Output 'PASS HDMI reset negative control: startup passed, post-recovery lane corruption rejected'
    }else{
        if($code -ne 0 -or $body -match '\bFAIL\b|\*\* (Error|Fatal):|Failed to open' -or -not $body.Contains("PASS $top")){throw "Failed reset recovery: $log"}
        Write-Output "PASS $top"
    }
} finally {Pop-Location}
