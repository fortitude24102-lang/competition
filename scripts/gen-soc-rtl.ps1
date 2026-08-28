param()

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'chisel-env.ps1')

function Assert-LastExitCode([string]$gate) {
    if ($LASTEXITCODE -ne 0) {
        throw "$gate failed with exit code $LASTEXITCODE"
    }
}

$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
$wslProjectRoot = "/mnt/$drive$pathWithoutDrive"

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/gen-soc-rtl.sh"
Assert-LastExitCode 'SoCTop RTL generation'

$topFile = Join-Path $projectRoot 'generated\SoCTop.sv'
if (-not (Test-Path -LiteralPath $topFile -PathType Leaf)) {
    throw "SoCTop RTL was not generated: $topFile"
}
$socTopFile = Join-Path $projectRoot 'generated\soc\SoCTop.sv'
if (-not (Test-Path -LiteralPath $socTopFile -PathType Leaf)) {
    throw "Isolated SoCTop RTL was not generated: $socTopFile"
}

$coreFile = Join-Path $projectRoot 'generated\Rv32Core.sv'
$coreText = Get-Content -LiteralPath $coreFile -Raw
foreach ($port in @('io_imem_req_bits_write', 'io_imem_req_bits_size', 'io_imem_req_bits_wdata', 'io_imem_req_bits_wstrb')) {
    if ($coreText -notmatch "\b$port\b") {
        throw "Standalone Rv32Core RTL lost port $port"
    }
}

Write-Host "[PASS] generated SoCTop RTL and preserved standalone Rv32Core ports"
