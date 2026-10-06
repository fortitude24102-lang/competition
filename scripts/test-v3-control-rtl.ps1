param([switch]$Legacy, [switch]$Scoped, [string]$IcarusRoot='C:/iverilog')
$ErrorActionPreference='Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$out='generated/verification/v3/control-rtl'
New-Item -ItemType Directory -Force $out | Out-Null
$iverilog=Join-Path $IcarusRoot 'bin/iverilog.exe'
$vvp=Join-Path $IcarusRoot 'bin/vvp.exe'
$net=@(Get-ChildItem board/efinix_ti60/rtl/net/*.v | ForEach-Object FullName)
$fifo=@('board/efinix_ti60/rtl/display/pixel_async_fifo.v','board/efinix_ti60/vendor/sapphire_ddr3/rtl/ddr3_controller/common/efx_fifo_v2.3/efx_fifo_wrapper.v')
$mac=@(Get-ChildItem board/efinix_ti60/vendor/ge_udp/rtl/heijin_test/mac -Filter *.v -Recurse | ForEach-Object FullName)
$tops=if($Legacy){@('tb_asset_udp_rx','tb_asset_network')}else{@('tb_net_async_mailbox','tb_net_control','tb_net_control_arbiter','tb_net_control_mac')}
if(!$Legacy -and !$Scoped){$tops+=@('tb_asset_udp_rx','tb_asset_network')}
foreach($top in $tops){
  $exe=Join-Path $out "$top.vvp"
  $ErrorActionPreference='Continue' # Native stderr includes read-only vendor warnings.
  & $iverilog -g2012 -s $top -o $exe "tb/verilog/$top.sv" @net @fifo @mac 2> "$out/$top-build.log"
  if($LASTEXITCODE -ne 0){Get-Content "$out/$top-build.log";throw "$top compilation failed"}
  & $vvp $exe 2>&1 | Tee-Object "$out/$top-result.log"
  if($LASTEXITCODE -ne 0){throw "$top failed"}
  $ErrorActionPreference='Stop'
}
