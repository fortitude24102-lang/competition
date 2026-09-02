param(
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Iterations = 1,
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Name = 'coremark_smoke'
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
$wslProjectRoot = "/mnt/$drive$pathWithoutDrive"

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/build-coremark.sh" $Iterations $Name
if ($LASTEXITCODE -ne 0) {
    throw "CoreMark image build failed with exit code $LASTEXITCODE"
}

Write-Host "[PASS] RV32I CoreMark image built ($Iterations iterations)"
