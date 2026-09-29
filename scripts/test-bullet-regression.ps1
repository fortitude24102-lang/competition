param([string]$HostGcc='gcc',[string]$Python='C:/efinity/efinity/python311/bin/python.exe')
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedPythonHome=$env:PYTHONHOME
$savedAssetDir=$env:ASSET_SERVER_TEST_DIRECTORY
try {
 if($Python -like '*/python311/bin/python.exe') {$env:PYTHONHOME=Split-Path (Split-Path $Python)}
 $out='generated/verification/bullet-demo/regression'
 New-Item -ItemType Directory -Force $out | Out-Null
 $flags=@('-std=c11','-O2','-Wall','-Wextra','-Werror','-D__USE_MINGW_ANSI_STDIO=1',
  '-Isw/efinix_gpu/include','-Isw/efinix_gpu/assets/v2')
 function Run([string]$test,[string[]]$modules,[switch]$Backend) {
  $sources=@("sw/efinix_gpu/tests/test_$test.c")+@($modules | ForEach-Object {"sw/efinix_gpu/src/$_.c"})
  [string[]]$extra=@()
  if($Backend){$extra+= '-DGPU_TEST_BACKEND'}
  & $HostGcc @flags @extra @sources -o "$out/$test.exe"
  if($LASTEXITCODE -ne 0){throw "compile $test failed"}
  & "./$out/$test.exe"
  if($LASTEXITCODE -ne 0){throw "$test failed"}
 }
 Run 'software' @('rgb565','golden_renderer')
 Run 'driver' @('gpu','rgb565','golden_renderer') -Backend
 Run 'copy' @('rgb565','golden_renderer')
 Run 'benchmark' @('gpu','benchmark','rgb565','golden_renderer') -Backend
 Run 'day9_13' @('gpu','assets','sparse_pack','framebuffer','hud','game','rgb565','golden_renderer') -Backend
 Run 'days16_20' @('gpu','assets','sparse_pack','benchmark','game','hud','rgb565','golden_renderer') -Backend
 Run 'sparse' @('sparse_pack','assets')
 Run 'days21_23' @('gpu','benchmark','game','assets','sparse_pack','hud','rgb565','golden_renderer') -Backend
 Run 'lane_game' @('lane_game','lane_scene','asset_protocol')
 Run 'asset_dma' @('asset_dma') -Backend
 Run 'network_assets' @('network_assets','asset_dma','asset_protocol') -Backend
 Run 'v2_assets' @('net_asset_server','asset_protocol','asset_cache')
 & $HostGcc @flags sw/efinix_gpu/tools/asset_server/asset_server.c sw/efinix_gpu/src/asset_protocol.c sw/efinix_gpu/src/net_asset_server.c -lws2_32 -o "$out/asset_server.exe"
 if($LASTEXITCODE -ne 0){throw 'asset server build failed'}
 & ./scripts/test-bullet-asset-server-launcher.ps1 -ServerPath "$out/asset_server.exe"
 if($LASTEXITCODE -ne 0){throw 'asset server launcher failed'}
 foreach($catalog in @('v2','bullet')) {
  $env:ASSET_SERVER_TEST_DIRECTORY="sw/efinix_gpu/assets/$catalog"
  & $Python sw/efinix_gpu/tests/test_asset_server_udp.py "$out/asset_server.exe"
  if($LASTEXITCODE -ne 0){throw "UDP catalog $catalog failed"}
 }
 Write-Output 'PASS native regression: 12 existing C suites, foreground launcher, V2 and bullet UDP catalogs'
} finally {
 $env:PYTHONHOME=$savedPythonHome
 $env:ASSET_SERVER_TEST_DIRECTORY=$savedAssetDir
 Pop-Location
}
