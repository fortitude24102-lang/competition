param()

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $projectRoot
. (Join-Path $PSScriptRoot 'chisel-env.ps1')

function Assert-LastExitCode([string]$gate) {
    if ($LASTEXITCODE -ne 0) {
        throw "$gate failed with exit code $LASTEXITCODE"
    }
}

$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$pathWithoutDrive = $projectRoot.Substring(2).Replace('\', '/')
$wslProjectRoot = "/mnt/$drive$pathWithoutDrive"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\test-video-rtl.ps1')
Assert-LastExitCode 'standalone video RTL regression'
Write-Host '[PASS] standalone video RTL regression'

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\build-software-test.ps1')
Assert-LastExitCode 'C software validation image'
Write-Host '[PASS] C software validation image built'

foreach ($image in @('driver_test.hex', 'driver_test_fail.hex', 'cli.hex', 'pango_bringup.hex', 'machine_trap.hex')) {
    $imagePath = Join-Path $projectRoot "sw\build\$image"
    if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
        throw "Software build did not produce $imagePath"
    }
}
Write-Host '[PASS] software: driver and interactive CLI images are present'

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/build-soc-smoke.sh"
Assert-LastExitCode 'SoC smoke program build'
Write-Host '[PASS] software: RV32I SoC smoke image rebuilt'

& wsl.exe -d Ubuntu -- bash "$wslProjectRoot/scripts/test-chisel.sh"
Assert-LastExitCode 'complete Chisel test suite'
Write-Host '[PASS] simulation: complete CPU and SoC test suite'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'gen-soc-rtl.ps1')
Assert-LastExitCode 'SoCTop RTL generation'

$generatedDirectory = Join-Path $projectRoot 'generated'
$socGeneratedDirectory = Join-Path $generatedDirectory 'soc'
$topFile = Join-Path $generatedDirectory 'SoCTop.sv'
$topText = Get-Content -LiteralPath $topFile -Raw
if ($topText -notmatch 'module\s+SoCTop\b') {
    throw 'generated/SoCTop.sv does not declare module SoCTop'
}
if ($topText -notmatch '\bVideoAccelTop\b') {
    throw 'generated/SoCTop.sv does not instantiate VideoAccelTop'
}
$coreText = Get-Content -LiteralPath (Join-Path $generatedDirectory 'Rv32Core.sv') -Raw
foreach ($port in @('io_imem_req_bits_write', 'io_imem_req_bits_size', 'io_imem_req_bits_wdata', 'io_imem_req_bits_wstrb')) {
    if ($coreText -notmatch "\b$port\b") {
        throw "Standalone Rv32Core RTL lost port $port"
    }
}

$rtlFiles = Get-ChildItem -LiteralPath $socGeneratedDirectory -Filter *.sv | Sort-Object Name
$externalVideo = Join-Path $projectRoot 'rtl\video\VideoAccelTop.v'
$projectPrefix = $projectRoot.TrimEnd('\') + '\'
$allRtl = @($rtlFiles.FullName) + @($externalVideo) |
    ForEach-Object {
        if (-not $_.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "RTL file is outside the project root: $_"
        }
        $_.Substring($projectPrefix.Length).Replace('\', '/')
    }
$fileList = Join-Path $generatedDirectory 'soc-filelist.f'
$allRtl | Set-Content -LiteralPath $fileList -Encoding ascii

& verilator --lint-only --top-module SoCTop -f $fileList
Assert-LastExitCode 'SoCTop Verilator lint'
Write-Host '[PASS] RTL: generated SoCTop and external VideoAccelTop resolve together'

$reportDirectory = Join-Path $generatedDirectory 'reports\soc-demo'
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$vivadoScript = Join-Path $PSScriptRoot 'vivado-soc.tcl'
$vivadoOutput = & vivado -mode batch -nojournal -nolog -notrace -source $vivadoScript `
    -tclargs $fileList $reportDirectory 2>&1
$vivadoOutput | Tee-Object -FilePath (Join-Path $reportDirectory 'vivado.log')
Assert-LastExitCode 'SoCTop Vivado checkpoint'

$requiredMetrics = @('SOC_WNS', 'SOC_LOGIC_LEVELS', 'SOC_STARTPOINT', 'SOC_ENDPOINT', 'SOC_LUT', 'SOC_FF', 'SOC_BRAM', 'SOC_DSP')
$metrics = @{}
foreach ($name in $requiredMetrics) {
    $line = $vivadoOutput | Where-Object { $_ -match "^$name=" } | Select-Object -Last 1
    if (-not $line) {
        throw "Vivado output did not contain $name"
    }
    $metrics[$name] = ($line -split '=', 2)[1]
}
if ([double]$metrics['SOC_WNS'] -lt 0) {
    throw "SoCTop timing failed: WNS=$($metrics['SOC_WNS']) ns"
}
$timingSummary = Get-Content -LiteralPath (Join-Path $reportDirectory 'timing_summary.rpt') -Raw
if ($timingSummary -match 'There are [1-9][0-9]* input ports with no input delay specified' -or
    $timingSummary -match 'There are [1-9][0-9]* output ports with no output delay specified') {
    throw 'SoCTop timing report contains unconstrained I/O ports'
}
Write-Host "[PASS] Vivado: WNS=$($metrics['SOC_WNS']) ns, levels=$($metrics['SOC_LOGIC_LEVELS']), LUT/FF/BRAM/DSP=$($metrics['SOC_LUT'])/$($metrics['SOC_FF'])/$($metrics['SOC_BRAM'])/$($metrics['SOC_DSP'])"

$binaryLeaks = git -C $projectRoot status --short --untracked-files=all |
    Where-Object { $_ -match '(chisel/src/test/resources|sw/build)/.*\.(bin|elf|hex|map)$' }
if ($binaryLeaks) {
    throw "Generated test images are visible to Git: $($binaryLeaks -join ', ')"
}
Write-Host '[PASS] repository hygiene: generated ELF/bin/hex files remain ignored'
Write-Host 'Chisel SoC milestone verification passed.'
