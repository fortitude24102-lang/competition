param(
    [string]$IcarusHome = 'D:/FPGA/iverilog',
    [string]$EvidenceDirectory = 'docs/efinix_2d_gpu/evidence'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iverilog = Join-Path $IcarusHome 'bin/iverilog.exe'
$vvp = Join-Path $IcarusHome 'bin/vvp.exe'

foreach ($tool in @($iverilog, $vvp)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing Windows Icarus tool: $tool"
    }
}

$tempRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ("efinix-member-a-" + [guid]::NewGuid().ToString('N'))))
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (!$tempRoot.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use non-temporary build directory: $tempRoot"
}
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null

$board = Join-Path $projectRoot 'board/efinix_ti60'
$rtl = Join-Path $board 'rtl'
$display = Join-Path $rtl 'display'
$pixel = Join-Path $rtl 'pixel'
$testbench = Join-Path $projectRoot 'tb/verilog'
$vendor = Join-Path $board 'vendor'
$encoder = Join-Path $vendor 'hdmi_tx/rtl/hdmi_src/dvi_tx'
$fifo = Join-Path $vendor 'sapphire_ddr3/rtl/ddr3_controller/common/efx_fifo_v2.3/efx_fifo_wrapper.v'

function Invoke-IcarusTest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Top,
        [Parameter(Mandatory)][string[]]$Sources,
        [string[]]$IncludeDirectories = @()
    )

    $output = Join-Path $tempRoot "$Name.vvp"
    $arguments = @('-g2012', '-s', $Top, '-o', $output)
    foreach ($include in $IncludeDirectories) {
        $arguments += @('-I', $include)
    }
    $arguments += $Sources

    Write-Output "[RUN] $Name"
    & $iverilog @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Icarus elaboration failed for $Name (exit $LASTEXITCODE)."
    }

    Push-Location $projectRoot
    try {
        & $vvp $output
        if ($LASTEXITCODE -ne 0) {
            throw "Icarus simulation failed for $Name (exit $LASTEXITCODE)."
        }
    } finally {
        Pop-Location
    }
}

try {
    $version = (& $iverilog -V 2>&1 | Select-Object -First 1)
    Write-Output "[INFO] $version"

    $rtlFiles = @(Get-ChildItem -LiteralPath $rtl -Recurse -File -Filter '*.v')
    foreach ($source in $rtlFiles) {
        $moduleCount = [regex]::Matches(
            (Get-Content -LiteralPath $source.FullName -Raw),
            '(?m)^\s*module\s+'
        ).Count
        if ($moduleCount -ne 1) {
            throw "Self-written RTL must contain one module per file: $($source.FullName) has $moduleCount."
        }
    }
    Write-Output "PASS self-written Verilog module structure: $($rtlFiles.Count) files"

    Invoke-IcarusTest -Name 'rgb565' -Top 'tb_rgb565_to_rgb888' -Sources @(
        (Join-Path $display 'rgb565_to_rgb888.v'),
        (Join-Path $testbench 'tb_rgb565_to_rgb888.sv')
    )

    Invoke-IcarusTest -Name 'hdmi-adapter' -Top 'tb_hdmi_tx_adapter' -Sources @(
        (Join-Path $display 'hdmi_tx_adapter.v'),
        (Join-Path $encoder 'dvi_encoder.v'),
        (Join-Path $encoder 'encode.v'),
        (Join-Path $testbench 'tb_hdmi_tx_adapter.sv')
    )

    Invoke-IcarusTest -Name 'pixel-pipe' -Top 'tb_gpu_pixel_pipe' -IncludeDirectories @($pixel) -Sources @(
        (Join-Path $pixel 'gpu_pixel_copy.v'),
        (Join-Path $pixel 'gpu_pixel_fill.v'),
        (Join-Path $pixel 'gpu_pixel_color_key.v'),
        (Join-Path $pixel 'gpu_pixel_alpha_blend.v'),
        (Join-Path $pixel 'gpu_pixel_pipe.v'),
        (Join-Path $testbench 'tb_gpu_pixel_pipe.sv')
    )

    Invoke-IcarusTest -Name 'vblank-cdc' -Top 'tb_vblank_pulse_sync' -Sources @(
        (Join-Path $display 'vblank_pulse_sync.v'),
        (Join-Path $testbench 'tb_vblank_pulse_sync.sv')
    )

    Invoke-IcarusTest -Name 'underflow-cdc' -Top 'tb_underflow_pulse_cdc' -Sources @(
        (Join-Path $display 'underflow_pulse_cdc.v'),
        (Join-Path $testbench 'tb_underflow_pulse_cdc.sv')
    )

    Invoke-IcarusTest -Name 'scale2x' -Top 'tb_display_scale2x_1080p' -Sources @(
        (Join-Path $display 'display_scale2x_1080p.v'),
        (Join-Path $testbench 'tb_display_scale2x_1080p.sv')
    )

    Invoke-IcarusTest -Name 'hdmi-subsystem' -Top 'tb_hdmi_subsystem' -Sources @(
        $fifo,
        (Join-Path $encoder 'dvi_encoder.v'),
        (Join-Path $encoder 'encode.v'),
        (Join-Path $display 'pixel_async_fifo.v'),
        (Join-Path $display 'display_line_buffer.v'),
        (Join-Path $display 'display_scale2x_1080p.v'),
        (Join-Path $display 'vblank_pulse_sync.v'),
        (Join-Path $display 'underflow_pulse_cdc.v'),
        (Join-Path $display 'rgb565_to_rgb888.v'),
        (Join-Path $display 'hdmi_tx_adapter.v'),
        (Join-Path $display 'hdmi_subsystem.v'),
        (Join-Path $testbench 'tb_hdmi_subsystem.sv')
    )

    $sourceVcd = Join-Path $testbench 'underflow_pulse_cdc.vcd'
    if (!(Test-Path -LiteralPath $sourceVcd -PathType Leaf)) {
        throw "Underflow CDC simulation did not produce its VCD: $sourceVcd"
    }
    $evidence = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
        [IO.Path]::GetFullPath($EvidenceDirectory)
    } else {
        [IO.Path]::GetFullPath((Join-Path $projectRoot $EvidenceDirectory))
    }
    [IO.Directory]::CreateDirectory($evidence) | Out-Null
    $evidenceVcd = Join-Path $evidence 'member_a_underflow_final.vcd'
    Copy-Item -LiteralPath $sourceVcd -Destination $evidenceVcd -Force
    Write-Output "[EVIDENCE] $evidenceVcd"
    Write-Output 'PASS member A direct-Windows-Icarus regression: 7 simulations'
} finally {
    if ([IO.Directory]::Exists($tempRoot)) {
        [IO.Directory]::Delete($tempRoot, $true)
    }
}
