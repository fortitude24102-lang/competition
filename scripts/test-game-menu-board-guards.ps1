# Offline only: every case must reject before opening serial/JTAG.
$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot 'test-game-menu-board.ps1'
$root=Split-Path $PSScriptRoot -Parent
$bin=Join-Path $root 'generated/verification/v3/submit_shadow_20261007/normal-default-restored/gpu_demo.bin'
function Reject($expected,$argsForTest) {
 $ErrorActionPreference='Continue' # Inspect expected native stderr/exit together.
 $text=& powershell -NoProfile -File $script @argsForTest 2>&1 | Out-String
 $ErrorActionPreference='Stop'
 if($LASTEXITCODE -eq 0 -or $text -notmatch $expected) {throw "Guard missing: $expected; $text"}
}
Reject 'Missing BIN' @('-Bin',"$root/absent-game-menu.bin",'-OutDirectory',"$root/generated/verification/v3/guard-unused")
Reject 'Missing BIT' @('-Bin',$bin,'-LoadBit','-OutDirectory',"$root/generated/verification/v3/guard-unused")
Reject 'Refusing to overwrite' @('-Bin',$bin,'-OutDirectory',"$root/generated/verification/v3")
Reject 'local gateway' @('-Bin',$bin,'-GatewayUrl','http://example.com:8765','-OutDirectory',"$root/generated/verification/v3/guard-unused")
'PASS offline board guards; no serial/JTAG opened'
