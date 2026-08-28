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

Write-Host "[PASS] generated $topFile"
