$ErrorActionPreference = 'Stop'

$toolchainHome = 'D:\Chisel-environment\riscv-toolchain'

& wsl.exe -d Ubuntu -- bash /mnt/d/ZYNQ/smallproject/scripts/setup-riscv-toolchain.sh
if ($LASTEXITCODE -ne 0) {
    throw "RISC-V toolchain setup failed with exit code $LASTEXITCODE"
}

[Environment]::SetEnvironmentVariable('RISCV_TOOLCHAIN_HOME', $toolchainHome, 'User')
$env:RISCV_TOOLCHAIN_HOME = $toolchainHome

Write-Output "RISCV_TOOLCHAIN_HOME=$toolchainHome"
