param()

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
$wslProjectRoot = "/mnt/$drive$pathWithoutDrive"

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/build-software-test.sh"
if ($LASTEXITCODE -ne 0) {
    throw "C software validation image build failed with exit code $LASTEXITCODE"
}

Write-Host '[PASS] C software validation image built'
