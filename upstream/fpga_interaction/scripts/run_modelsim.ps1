param([string]$SimDirectory = "")

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$simDir = if ($SimDirectory) { $SimDirectory } else { Join-Path $root "sim" }
if (-not (Test-Path -LiteralPath $simDir)) {
    New-Item -ItemType Directory -Path $simDir | Out-Null
}
Set-Location $simDir

if (-not (Test-Path -LiteralPath "work")) {
    & "D:\Modelsim\win64\vlib.exe" work
}

$sources = @(
    "..\rtl\input_sync_debounce.v",
    "..\rtl\touch_or_key_if.v",
    "..\rtl\pressure_if.v",
    "..\rtl\adc_knob_if.v",
    "..\rtl\i2c_master.v",
    "..\rtl\ads1115_if.v",
    "..\rtl\ads1115_knob_if.v",
    "..\rtl\event_encoder.v",
    "..\rtl\voice_allocator.v",
    "..\rtl\reset_sync.v",
    "..\rtl\voice_test_pattern.v",
    "..\rtl\interaction_top.v",
    "..\rtl\board_top.v",
    "..\rtl\board_test_top.v",
    "..\rtl\board_knob_top.v",
    "..\tb\tb_input_sync_debounce.sv",
    "..\tb\tb_pressure_if.sv",
    "..\tb\tb_adc_knob_if.sv",
    "..\tb\tb_event_encoder.sv",
    "..\tb\tb_voice_allocator.sv",
    "..\tb\tb_interaction_top.sv",
    "..\tb\tb_voice_test_pattern.sv",
    "..\tb\tb_keyboard_extended.sv",
    "..\tb\ads1115_model.sv",
    "..\tb\tb_ads1115_if.sv",
    "..\tb\tb_ads1115_knob_if.sv",
    "..\tb\tb_ads1115_faults.sv",
    "..\tb\tb_ads1115_mapping.sv"
)
$sources = @($sources | ForEach-Object {
    Join-Path $root $_.Substring(3)
})

& "D:\Modelsim\win64\vlog.exe" -sv @sources
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$tests = @(
    "tb_input_sync_debounce",
    "tb_input_sync_debounce_2ms",
    "tb_pressure_if",
    "tb_adc_knob_if",
    "tb_event_encoder",
    "tb_voice_allocator",
    "tb_interaction_top",
    "tb_voice_test_pattern",
    "tb_keyboard_extended",
    "tb_ads1115_if",
    "tb_ads1115_knob_if",
    "tb_ads1115_faults",
    "tb_ads1115_mapping"
)

foreach ($test in $tests) {
    Write-Host "===== RUN $test ====="
    $simOutput = @(& "D:\Modelsim\win64\vsim.exe" -c -onfinish exit "work.$test" -do "run -all; quit -code 0 -f")
    $simExit = $LASTEXITCODE
    $simOutput | ForEach-Object { Write-Host $_ }
    if (($simExit -ne 0) -or ($simOutput -match 'FAIL:|\*\* (Error|Fatal):') -or
        -not ($simOutput -match 'PASS:')) {
        Write-Error "Simulation failed or missing PASS: $test (exit=$simExit)"
        exit 1
    }
}
