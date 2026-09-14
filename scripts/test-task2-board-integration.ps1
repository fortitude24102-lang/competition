param([switch]$StaticOnly)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$board = Join-Path $projectRoot 'board/efinix_ti60'
$projectFile = Join-Path $board 'efinix_2d_gpu.xml'
$cdcRelative = 'rtl/display/underflow_pulse_cdc.v'
$hdmiRelative = 'rtl/display/hdmi_subsystem.v'
$boardTopRelative = 'rtl/board_top.v'
$cdcSourcePath = Join-Path $board $cdcRelative
$iverilog = 'D:\FPGA\iverilog\bin\iverilog.exe'
$vvp = 'D:\FPGA\iverilog\bin\vvp.exe'

if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) {
    throw 'Direct Windows Icarus tools are required at D:\FPGA\iverilog\bin.'
}

[xml]$project = Get-Content -Raw $projectFile
$ns = New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$ns.AddNamespace('e', 'http://www.efinixinc.com/enf_proj')
$sourceList = @($project.SelectNodes('//e:design_file', $ns) | ForEach-Object { $_.name })
$cdcIndex = [Array]::IndexOf($sourceList, $cdcRelative)
$hdmiIndex = [Array]::IndexOf($sourceList, $hdmiRelative)

if ($cdcIndex -lt 0) {
    throw "FAIL project elaboration: $cdcRelative is absent from the Efinity source list."
}
if ($hdmiIndex -lt 0 -or $cdcIndex -gt $hdmiIndex) {
    throw "FAIL project elaboration: $cdcRelative must precede $hdmiRelative."
}
if ([Array]::IndexOf($sourceList, $boardTopRelative) -lt 0) {
    throw "FAIL project elaboration: $boardTopRelative is absent from the Efinity source list."
}

$boardTop = Get-Content -Raw (Join-Path $board $boardTopRelative)
if ($boardTop -notmatch '(?m)^\s*\(\*\s*syn_keep\s*=\s*"true"\s*\*\)\s*wire\s+gpu_underflow_pulse\s*;') {
    throw 'FAIL board integration: the unconsumed lead handoff must be syn_keep until its counter port exists.'
}
if ($boardTop -notmatch '\.underflow_pulse_gpu\s*\(\s*gpu_underflow_pulse\s*\)') {
    throw 'FAIL board integration: hdmi_subsystem must drive gpu_underflow_pulse.'
}

$cdcSource = Get-Content -Raw $cdcSourcePath
if ($cdcSource -notmatch '(?m)^\s*\(\*\s*syn_keep\s*=\s*"true"\s*\*\)\s*reg\s+\[EVENT_COUNTER_WIDTH-1:0\]\s+pixel_event_gray\s*;') {
    throw 'FAIL constraints: Efinity must preserve every registered Gray source bit with syn_keep.'
}

$constraints = Get-Content -Raw (Join-Path $board 'efinix_2d_gpu.sdc')
if ($constraints -match '\bget_registers\b') {
    throw 'FAIL constraints: Efinity 2026.1 does not provide the get_registers SDC command.'
}
if ($constraints -notmatch 'set_max_delay\s+6\.722689076[\s\S]*?get_cells\s+\{\*u_underflow_sync\*pixel_event_gray\*\}[\s\S]*?get_cells\s+\{\*u_underflow_sync\*gpu_gray_sync0\*\}') {
    throw 'FAIL constraints: registered Gray CDC path must use Efinity-compatible get_cells selectors.'
}

if ($StaticOnly) {
    Write-Output 'PASS board project integration static checks'
    return
}

$vvpOutput = Join-Path $env:TEMP 'task2-underflow-pulse-cdc.vvp'
& $iverilog -g2012 -s tb_underflow_pulse_cdc -o $vvpOutput `
    (Join-Path $board $cdcRelative) `
    (Join-Path $projectRoot 'tb/verilog/tb_underflow_pulse_cdc.sv')
if ($LASTEXITCODE -ne 0) { throw "FAIL pulse elaboration: iverilog exited $LASTEXITCODE." }
& $vvp $vvpOutput
if ($LASTEXITCODE -ne 0) { throw "FAIL pulse behavior: vvp exited $LASTEXITCODE." }

Write-Output 'PASS board project integration and underflow CDC pulse behavior'
