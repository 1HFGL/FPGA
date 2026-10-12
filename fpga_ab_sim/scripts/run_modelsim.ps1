$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$filesRoot = Split-Path -Parent $root
$simDir = Join-Path $root "sim"
Set-Location $simDir
if (-not (Test-Path -LiteralPath "work")) { & "D:\Modelsim\win64\vlib.exe" work }
$sources = @(
    "$filesRoot\fpga_interaction\rtl\input_sync_debounce.v",
    "$filesRoot\fpga_interaction\rtl\touch_or_key_if.v",
    "$filesRoot\fpga_interaction\rtl\pressure_if.v",
    "$filesRoot\fpga_interaction\rtl\adc_knob_if.v",
    "$filesRoot\fpga_interaction\rtl\event_encoder.v",
    "$filesRoot\fpga_interaction\rtl\voice_allocator.v",
    "$filesRoot\fpga_interaction\rtl\voice_test_pattern.v",
    "$filesRoot\fpga_interaction\rtl\interaction_top.v",
    "$filesRoot\fpga_a\rtl\phase_inc_calc.v",
    "$filesRoot\fpga_a\rtl\wave_lut.v",
    "$filesRoot\fpga_a\rtl\adsr_envelope.v",
    "$filesRoot\fpga_a\rtl\voice_gain.v",
    "$filesRoot\fpga_a\rtl\poly_mixer_saturator.v",
    "$filesRoot\fpga_a\rtl\synth_engine.v",
    "$filesRoot\fpga_b\rtl\sample_tick_gen.v",
    "$filesRoot\fpga_b\rtl\i2s_tx.v",
    "$root\rtl\audio_system_top.v",
    "$root\tb\tb_c_ab_system.sv",
    "$root\tb\tb_c_ab_system_32.sv"
)
& "D:\Modelsim\win64\vlog.exe" -sv @sources
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$tests = @("tb_c_ab_system", "tb_c_ab_system_32")
foreach ($test in $tests) {
    Write-Host "===== RUN $test ====="
    & "D:\Modelsim\win64\vsim.exe" -c "work.$test" -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}