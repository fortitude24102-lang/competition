$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$environmentScript = Join-Path $PSScriptRoot 'chisel-env.ps1'

if (-not (Test-Path -LiteralPath $environmentScript -PathType Leaf)) {
    throw "Missing environment script: $environmentScript"
}

. $environmentScript

$malformedPathEntries = $env:Path -split ';' | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' }
if ($malformedPathEntries) {
    throw "Malformed PATH entries remain: $($malformedPathEntries -join ', ')"
}

foreach ($command in 'java', 'sbt', 'verilator', 'git', 'vivado') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is unavailable: $command"
    }
}

Push-Location (Join-Path $projectRoot 'chisel')
try {
    & sbt 'runMain Generate --target-dir ../generated'
    if ($LASTEXITCODE -ne 0) {
        throw "Chisel generation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$generatedRtl = Join-Path $projectRoot 'generated\Blink.sv'
if (-not (Test-Path -LiteralPath $generatedRtl -PathType Leaf)) {
    throw "Missing generated RTL: $generatedRtl"
}

$rtl = Get-Content -Raw -LiteralPath $generatedRtl
foreach ($pattern in 'module\s+Blink', '\bclock\b', '\breset\b', '\bio_led\b') {
    if ($rtl -notmatch $pattern) {
        throw "Generated RTL does not satisfy contract: $pattern"
    }
}

& verilator --lint-only --top-module Blink $generatedRtl
if ($LASTEXITCODE -ne 0) {
    throw "Verilator lint failed with exit code $LASTEXITCODE"
}

$vivadoCheck = Join-Path $PSScriptRoot 'vivado-check.tcl'
if (-not (Test-Path -LiteralPath $vivadoCheck -PathType Leaf)) {
    throw "Missing Vivado check script: $vivadoCheck"
}

& vivado -mode batch -nojournal -nolog -notrace -source $vivadoCheck -tclargs $generatedRtl
if ($LASTEXITCODE -ne 0) {
    throw "Vivado RTL elaboration failed with exit code $LASTEXITCODE"
}

Write-Host 'Day 0-1 verification passed.'
