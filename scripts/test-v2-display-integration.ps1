$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$board = Join-Path $root 'board/efinix_ti60'
[xml]$project = Get-Content -Raw (Join-Path $board 'efinix_2d_gpu.xml')
$ns = [Xml.XmlNamespaceManager]::new($project.NameTable)
$ns.AddNamespace('e', 'http://www.efinixinc.com/enf_proj')
$sources = @($project.SelectNodes('//e:design_file', $ns) | ForEach-Object { $_.name })
foreach ($source in $sources) {
    if (!(Test-Path -LiteralPath (Join-Path $board $source))) { throw "Missing project source: $source" }
}
$expected = @(Get-Content (Join-Path $root 'generated/efinix_gpu/filelist.f') | ForEach-Object { $_.Trim() -replace '^\.[/\\]', '' } | Where-Object { $_ })
$actual = @($sources | Where-Object { $_ -like '../../generated/efinix_gpu/*' } | ForEach-Object { [IO.Path]::GetFileName($_) })
if (($actual -join "`n") -cne ($expected -join "`n")) { throw 'GPU filelist/order differs from frozen RC0' }
if (@($sources | Group-Object | Where-Object Count -gt 1).Count) { throw 'Duplicate project source' }
foreach ($line in Get-Content (Join-Path $root 'release/v2_rc0.sha256')) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw "Invalid manifest line: $line" }
    $expectedHash = $Matches[1]
    $path = $Matches[2]
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root $path)).Hash -ine $expectedHash) { throw "RC0 changed: $path" }
}
$top = Get-Content -Raw (Join-Path $board 'rtl/board_top.v')
$adapter = Get-Content -Raw (Join-Path $board 'rtl/efinix_sapphire_adapter.v')
$display = Get-Content -Raw (Join-Path $board 'rtl/display/hdmi_subsystem.v')
if ($top -notmatch '\.gpu_underflow_pulse_gpu\s*\(gpu_underflow_pulse\)' -or
    $top -notmatch '\.underflow_pulse_gpu\s*\(gpu_underflow_pulse\)' -or
    $adapter -notmatch '\.io_underflow_pulse_gpu\s*\(gpu_underflow_pulse_gpu\)' -or
    $display -notmatch 'underflow_pulse_cdc\s+u_underflow_sync') { throw 'Underflow handoff is disconnected' }
if ($sources -notcontains 'rtl/display/underflow_pulse_cdc.v') { throw 'Missing CDC project source' }
Write-Output 'PASS V2 display integration: project sources, ordered GPU filelist, frozen RC0 hashes, underflow handoff'
Write-Output 'Scope: structural checks only; network integration, Efinity timing and hardware remain pending.'
