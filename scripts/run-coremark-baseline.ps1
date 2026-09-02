param(
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Iterations = 1
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
$wslProjectRoot = "/mnt/$drive$pathWithoutDrive"

& (Join-Path $PSScriptRoot 'build-coremark.ps1') -Iterations $Iterations -Name coremark_smoke

$simOutput = & wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/run-coremark-sim.sh" "$wslProjectRoot/sw/build/coremark_smoke.hex" 2>&1
$simExitCode = $LASTEXITCODE
$simOutput | ForEach-Object { Write-Host $_ }
if ($simExitCode -ne 0) {
    throw "CoreMark RTL simulation failed with exit code $simExitCode"
}

$text = $simOutput -join "`n"
foreach ($required in @(
    '2K performance run parameters for coremark.',
    'seedcrc          : 0xe9f5',
    '[0]crclist       : 0xe714',
    '[0]crcmatrix     : 0x1fd7',
    '[0]crcstate      : 0x8e3a',
    'SIM_HALTED=1'
)) {
    if (-not $text.Contains($required)) {
        throw "CoreMark output is missing expected marker: $required"
    }
}
if ($text -match 'ERROR! (list|matrix|state) crc') {
    throw 'CoreMark algorithm CRC validation failed'
}

$ticksMatch = [regex]::Match($text, 'Total ticks\s*:\s*(\d+)')
$iterationsMatch = [regex]::Match($text, 'Iterations\s*:\s*(\d+)')
$cyclesMatch = [regex]::Match($text, 'SIM_CYCLES=(\d+)')
$verilatorMatch = [regex]::Match($text, 'SIM_VERILATOR_VERSION=(.+)')
if (-not ($ticksMatch.Success -and $iterationsMatch.Success -and $cyclesMatch.Success -and $verilatorMatch.Success)) {
    throw 'Could not extract CoreMark timing fields from RTL simulation output'
}

$ticks = [double]$ticksMatch.Groups[1].Value
$measuredIterations = [double]$iterationsMatch.Groups[1].Value
$simulationCycles = [uint64]$cyclesMatch.Groups[1].Value
$verilatorVersion = $verilatorMatch.Groups[1].Value.Trim()
$cyclesPerIteration = $ticks / $measuredIterations
$estimatedCoreMarkPerMhz = $measuredIterations * 1000000.0 / $ticks

$reportDirectory = Join-Path $projectRoot 'generated\reports'
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$reportPath = Join-Path $reportDirectory 'coremark-baseline.txt'
$report = @"
CoreMark RV32I RTL development baseline
=======================================
Status: non-reportable short simulation baseline
CoreMark source revision: 1f483d5b8316753a742cbf5590caf5bd0a4e4777
Compiler flags: -O2 -march=rv32i -mabi=ilp32
RTL simulator: $verilatorVersion
Data size: 2000 bytes
Measured iterations: $([uint64]$measuredIterations)
Timed CPU cycles: $([uint64]$ticks)
Cycles per iteration: $($cyclesPerIteration.ToString('F2'))
Estimated CoreMark/MHz: $($estimatedCoreMarkPerMhz.ToString('F4'))
Full simulation cycles: $simulationCycles
CRC validation: passed

This quick RTL result is for architecture comparison only. The contest result
must be rerun on the target FPGA for at least 10 seconds at the measured clock.
"@
Set-Content -LiteralPath $reportPath -Value $report -Encoding utf8

Write-Host "[PASS] CoreMark CRC validation passed"
Write-Host "[BASELINE] $($cyclesPerIteration.ToString('F2')) cycles/iteration"
Write-Host "[BASELINE] $($estimatedCoreMarkPerMhz.ToString('F4')) CoreMark/MHz (estimated, non-reportable)"
Write-Host "[REPORT] $reportPath"
