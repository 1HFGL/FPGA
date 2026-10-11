# 保存本轮可复现证据，不移动原始资料，也不保存/推送位流。
[CmdletBinding()]
param([string]$Destination='docs/reports/sync-review-20261011')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $all=Get-Content 'results/sync-review-all.log' -Raw
    if(-not $all.Contains('PASS: suite All (34 testbenches).')){throw 'All regression is incomplete'}
    $uart=Get-Content 'results/sync-review-uart.log' -Raw
    $piano=Get-Content 'results/sync-review-piano.log' -Raw
    if(([regex]::Matches($uart,'(?m)^VERIFIED ')).Count -ne 7){throw 'UART regression is incomplete'}
    if(([regex]::Matches($piano,'(?m)^VERIFIED ')).Count -ne 2){throw 'Piano regression is incomplete'}
    if((Get-Content 'results/sync-review-20261011/strict_compile.log' -Raw) -notmatch 'Errors: 0, Warnings: 0'){throw 'Strict compile failed'}
    New-Item -ItemType Directory -Path "$Destination/simulation","$Destination/build-piano","$Destination/build-instruments" -Force | Out-Null
    $tops=[regex]::Matches($all,'(?m)^VERIFIED (\w+)') | ForEach-Object {$_.Groups[1].Value}
    foreach($top in $tops){Copy-Item -LiteralPath "results/logs/$top.log" -Destination "$Destination/simulation"}
    Copy-Item -LiteralPath 'results/logs/All_sha256.txt' -Destination "$Destination/simulation"
    foreach($part in @('uart','piano')){
        Get-ChildItem "results/sync-review-20261011/$part" -File |
            Where-Object {$_.Extension -in @('.log','.txt') -and $_.Name -ne 'normal_compile.log'} |
            Copy-Item -Destination "$Destination/simulation"
    }
    # 两个目录都有normal_compile.log；按入口分别复制，防止同名覆盖丢证据。
    Copy-Item 'results/sync-review-20261011/uart/normal_compile.log' "$Destination/simulation/uart_compile.log"
    Copy-Item 'results/sync-review-20261011/piano/normal_compile.log' "$Destination/simulation/piano_compile.log"
    Copy-Item 'results/sync-review-20261011/strict_*.txt','results/sync-review-20261011/strict_*.log' -Destination $Destination
    Get-ChildItem 'results/sync-review-20261011/build-piano' -File | Copy-Item -Destination "$Destination/build-piano"
    Copy-Item -LiteralPath 'results/sync-review-20261011/instruments-board-audit.json','results/sync-review-instruments-build.log' -Destination "$Destination/build-instruments"
    Copy-Item -LiteralPath 'fpga_project/instruments_board/impl/pnr/instruments_board.rpt.txt','fpga_project/instruments_board/impl/pnr/instruments_board.tr' -Destination "$Destination/build-instruments"
    Copy-Item -LiteralPath 'results/sync-review-python.log' -Destination $Destination
    Write-Output "PASS: review evidence saved to $Destination"
} finally {Pop-Location}
