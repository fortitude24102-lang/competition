param()

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'chisel-env.ps1')
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
$wslProjectRoot = "/mnt/$drive$pathWithoutDrive"

function Assert-LastExitCode([string]$gate) {
    if ($LASTEXITCODE -ne 0) {
        throw "$gate failed with exit code $LASTEXITCODE"
    }
}

& wsl.exe -d Ubuntu -- /mnt/d/Chisel-environment/riscv-toolchain/usr/bin/riscv64-unknown-elf-gcc `
    -march=rv32i -mabi=ilp32 -dumpmachine
Assert-LastExitCode 'RV32I toolchain check'
Write-Host '[PASS] toolchain: RV32I/ILP32 compiler is available'

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/build-rv32i-tests.sh"
Assert-LastExitCode 'compiled smoke program build'
Write-Host '[PASS] program build: smoke.bin rebuilt'

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/build-rv32ui-tests.sh"
Assert-LastExitCode 'upstream rv32ui build'
Write-Host '[PASS] architecture build: 37 selected rv32ui binaries rebuilt'

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/test-chisel.sh"
Assert-LastExitCode 'Chisel test suite'
Write-Host '[PASS] component tests: decoder, execute, LSU, frontend, register file, and control'
Write-Host '[PASS] pipeline tests: arithmetic, control flow, memory latency, and precise traps'
Write-Host '[PASS] program test: compiled smoke signature and EBREAK'
Write-Host '[PASS] architecture tests: 37 selected upstream rv32ui binaries'

$generateCommand = @'
export JAVA_HOME=/mnt/d/Chisel-environment/wsl/java17-root/usr/lib/jvm/java-17-openjdk-amd64
export PATH=/mnt/d/Chisel-environment/wsl/java17-root/usr/lib/jvm/java-17-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export COURSIER_CACHE=/mnt/d/Chisel-environment/cache/coursier
export CHISEL_FIRTOOL_CACHE=/mnt/d/Chisel-environment/wsl/firtool-cache
export SBT_OPTS="-Dsbt.boot.directory=/mnt/d/Chisel-environment/cache/sbt/boot-wsl -Dsbt.global.base=/mnt/d/Chisel-environment/cache/sbt/global-wsl -Dsbt.ivy.home=/mnt/d/Chisel-environment/cache/ivy-wsl"
cd __PROJECT_ROOT__/chisel
bash /mnt/d/Chisel-environment/sbt/bin/sbt "runMain Generate rv32 --target-dir ../generated"
'@
$generateCommand = $generateCommand.Replace('__PROJECT_ROOT__', $wslProjectRoot)
& wsl.exe -d Ubuntu -- bash -lc $generateCommand
Assert-LastExitCode 'Rv32Core RTL generation'

$generatedDirectory = Join-Path $projectRoot 'generated'
$rtlFiles = Get-ChildItem -LiteralPath $generatedDirectory -Filter *.sv |
    Where-Object { $_.Name -ne 'Blink.sv' } |
    Sort-Object Name
& verilator --lint-only --top-module Rv32Core @($rtlFiles.FullName)
Assert-LastExitCode 'Rv32Core Verilator lint'
Write-Host '[PASS] RTL generation: Rv32Core SystemVerilog generated and linted'

$fileList = Join-Path $generatedDirectory 'filelist.f'
$rtlFiles.Name | Set-Content -LiteralPath $fileList -Encoding ascii
$reportDirectory = Join-Path $generatedDirectory 'reports\rv32core-final'
$vivadoScript = Join-Path $PSScriptRoot 'vivado-rv32-core.tcl'
$vivadoOutput = & vivado -mode batch -nojournal -nolog -notrace -source $vivadoScript `
    -tclargs $fileList $reportDirectory 2>&1
$vivadoOutput | Tee-Object -FilePath (Join-Path $reportDirectory 'vivado.log')
Assert-LastExitCode 'Rv32Core Vivado checkpoint'

$wnsLine = $vivadoOutput | Where-Object { $_ -match '^RV32CORE_WNS=' } | Select-Object -Last 1
$levelsLine = $vivadoOutput | Where-Object { $_ -match '^RV32CORE_LOGIC_LEVELS=' } | Select-Object -Last 1
if (-not $wnsLine -or -not $levelsLine) {
    throw 'Vivado output did not contain timing metrics'
}
$wns = [double](($wnsLine -split '=', 2)[1])
if ($wns -lt 0) {
    throw "Rv32Core timing failed: WNS=$wns ns"
}
Write-Host "[PASS] timing report: WNS=$wns ns, $levelsLine"

$binaryLeaks = git -C $projectRoot status --short --untracked-files=all |
    Where-Object { $_ -match 'chisel/src/test/resources/.*\.(bin|elf)$' }
if ($binaryLeaks) {
    throw "Generated test binaries are visible to Git: $($binaryLeaks -join ', ')"
}
Write-Host '[PASS] repository hygiene: generated ELF/bin files remain ignored'
Write-Host 'RV32I core milestone verification passed.'
