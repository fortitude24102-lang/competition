$ErrorActionPreference = 'Stop'

$toolchainHome = 'D:\Chisel-environment\riscv-toolchain'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
$wslProjectRoot = "/mnt/$drive$pathWithoutDrive"

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/setup-riscv-toolchain.sh"
if ($LASTEXITCODE -ne 0) {
    throw "RISC-V toolchain setup failed with exit code $LASTEXITCODE"
}

[Environment]::SetEnvironmentVariable('RISCV_TOOLCHAIN_HOME', $toolchainHome, 'User')
$env:RISCV_TOOLCHAIN_HOME = $toolchainHome

Write-Output "RISCV_TOOLCHAIN_HOME=$toolchainHome"
