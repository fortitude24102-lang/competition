param()
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
& wsl.exe -d Ubuntu -- bash "/mnt/$drive$pathWithoutDrive/scripts/test-efinix-verilog.sh"
if ($LASTEXITCODE -ne 0) {
    throw "Efinix Verilog regression failed with exit code $LASTEXITCODE"
}
Write-Host '[PASS] Efinix Verilog regression'
