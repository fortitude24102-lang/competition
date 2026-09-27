param([switch]$Lint)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$board = Join-Path $root 'board/efinix_ti60'
[xml]$project = Get-Content -Raw (Join-Path $board 'efinix_2d_gpu.xml')
$ns = [Xml.XmlNamespaceManager]::new($project.NameTable)
$ns.AddNamespace('e', 'http://www.efinixinc.com/enf_proj')
$sources = @($project.SelectNodes('//e:design_file', $ns) | ForEach-Object { $_.name })
foreach ($source in $sources) {
    if (!(Test-Path -LiteralPath (Join-Path $board $source))) { throw "Missing source: $source" }
}
if (@($sources | Group-Object | Where-Object Count -gt 1).Count) { throw 'Duplicate source' }
foreach ($source in Get-ChildItem (Join-Path $board 'rtl/net') -Filter *.v) {
    if ($sources -notcontains ('rtl/net/' + $source.Name)) { throw "Missing network source: $source" }
}
[xml]$peri = Get-Content -Raw (Join-Path $board 'efinix_2d_gpu.peri.xml')
$pn = [Xml.XmlNamespaceManager]::new($peri.NameTable)
$pn.AddNamespace('p', 'http://www.efinixinc.com/peri_design_db')
foreach ($resource in 'gpio_def','pll_def') {
    $used = @($peri.SelectNodes("//*[@$resource]", $pn) | ForEach-Object { $_.GetAttribute($resource) })
    if (@($used | Group-Object | Where-Object Count -gt 1).Count) { throw "Resource collision: $resource" }
}
$pll = $peri.SelectSingleNode('//p:pll[@name="ge_0_gclk_pll"]', $pn)
if ($pll.pll_def -ne 'PLL_BL0' -or $pll.ref_clock_name -ne 'rxc') { throw 'GE PLL routing changed' }
foreach ($clock in 'ge0_tx_clk','ge0_tx_clk_90') {
    $node = $pll.SelectSingleNode("p:comp_output_clock[@name='$clock']", $pn)
    if ($node.phase_setting -ne '5' -or $node.out_divider -ne '10') { throw "GE phase changed: $clock" }
}
$top = Get-Content -Raw (Join-Path $board 'rtl/board_top.v')
$adapter = Get-Content -Raw (Join-Path $board 'rtl/efinix_sapphire_adapter.v')
$gpu = Get-Content -Raw (Join-Path $root 'generated/efinix_gpu/Efinix2dGpuTop.sv')
foreach ($port in [regex]::Matches($gpu.Split(');')[0], '\b(io_asset\w+)\b').Value | Sort-Object -Unique) {
    if ($adapter -notmatch ('\.' + $port + '\s*\(\w+\)')) { throw "Disconnected GPU asset port: $port" }
}
if ($adapter -notmatch "gpu_apb_paddr\[15:8\] == 8'h02" -or
    $adapter -notmatch 'gpu_apb_psel && !network_select' -or
    $adapter -notmatch 'gpu_apb_psel && network_select') { throw 'APB network demux absent' }
foreach ($node in $peri.SelectNodes('//p:comp_gpio[starts-with(@name,"rx") or starts-with(@name,"tx") or @name="phy_rst_n" or @name="mdc_o" or @name="mdio_io"]/*', $pn)) {
    foreach ($attribute in 'name','name_ddio_lo') {
        $signal = $node.GetAttribute($attribute) -replace '\[\d+\]$', ''
        if ($signal -and $attribute -eq 'name_ddio_lo' -and $node.ddio_type -eq 'none') { continue }
        if ($signal -and $top -notmatch ('\b' + [regex]::Escape($signal) + '\b')) { throw "Missing GE alias: $signal" }
    }
}
Write-Output 'PASS: network source list, unique pin/PLL resources, official GE phases, APB and every GPU asset port'
if ($Lint) {
    throw 'The official DDR controller contains encrypted RTL. Use test-efinix-board.ps1 -Flow map for full-board elaboration; use test-v2-network-rtl.sh for network simulation.'
}
