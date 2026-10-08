param(
 [Parameter(Mandatory=$true)][string]$Bin,
 [string]$Bit,
 [string]$GatewayUrl='http://127.0.0.1:8765',
 [Parameter(Mandatory=$true)][string]$OutDirectory,
 [switch]$LoadBit
)
# JTAG only. Real HTTP/UDP acknowledgements, not simulated game state.
# Plane movement, death, replay completion and visual checks remain manual.
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $Bin -PathType Leaf)) {throw "Missing BIN: $Bin"}
if($LoadBit -and (!$Bit -or !(Test-Path -LiteralPath $Bit -PathType Leaf))) {throw "Missing BIT: $Bit"}
if(Test-Path -LiteralPath $OutDirectory) {throw "Refusing to overwrite capture: $OutDirectory"}
$gateway=[uri]$GatewayUrl
if($gateway.Scheme -ne 'http' -or $gateway.Host -ne '127.0.0.1' -or $gateway.Port -ne 8765 -or $gateway.AbsolutePath -ne '/') {
 throw 'Use the local gateway http://127.0.0.1:8765; do not weaken Host/Origin checks'
}
$binPath=(Resolve-Path -LiteralPath $Bin).Path.Replace('\','/')
if($binPath -match '["{};\r\n]') {throw 'Unsupported JTAG path characters'}
$outPath=[IO.Path]::GetFullPath($OutDirectory)
$boot=Invoke-RestMethod "$GatewayUrl/api/bootstrap" -TimeoutSec 2
if($boot.simulated) {throw 'Refusing simulated peer for board qualification'}
New-Item -ItemType Directory $outPath | Out-Null
$serial=New-Object IO.Ports.SerialPort 'COM13',115200,'None',8,'One'
$serial.ReadTimeout=100
$client=[guid]::NewGuid().ToString('N');$held=0;$action=0;$request=0;$acquired=$false
$timer=[Diagnostics.Stopwatch]::StartNew();$lastKey=-1000.0;$lastStatus=-1000.0;$state=$null;$tail=''
function Capture {
 $chunk=$serial.ReadExisting()
 if($chunk) {
  [IO.File]::AppendAllText("$outPath/uart.log",$chunk)
  $script:tail+=$chunk
  if($script:tail -match 'V3_FAIL|V3_PROBE_HEALTH_FAIL|V2 comparison stopped') {throw 'Firmware failed; preserve capture and restore qualified bundle'}
  if($script:tail.Length -gt 16384) {$script:tail=$script:tail.Substring($script:tail.Length-8192)}
 }
}
function Post($path,$body) {
 Invoke-RestMethod "$GatewayUrl$path" -Method Post -ContentType 'application/json' -Headers @{Origin=$GatewayUrl} -Body ($body|ConvertTo-Json -Compress) -TimeoutSec 1
}
function Tick {
 Capture
 if($script:acquired -and $timer.Elapsed.TotalMilliseconds-$script:lastKey -ge 70) {
  $null=Post '/api/control' @{token=$boot.token;client=$client;keys=$script:held;action_sequence=$script:action;release=$false}
  $script:lastKey=$timer.Elapsed.TotalMilliseconds
 }
 if($timer.Elapsed.TotalMilliseconds-$script:lastStatus -ge 100) {
  $script:state=Invoke-RestMethod "$GatewayUrl/api/status" -TimeoutSec 1
  [IO.File]::AppendAllText("$outPath/http.jsonl",($script:state|ConvertTo-Json -Depth 8 -Compress)+"`n")
  $script:lastStatus=$timer.Elapsed.TotalMilliseconds
  if(!$script:state.stale -and $script:state.telemetry -and
   ($script:state.telemetry.raw.gpu_error_delta -or $script:state.telemetry.raw.scanout_underflow_delta)) {throw 'Board health counter nonzero'}
 }
 Start-Sleep -Milliseconds 10
}
function Wait($condition,$seconds,$label) {
 $deadline=$timer.Elapsed.TotalSeconds+$seconds
 do {Tick;if(& $condition) {return}} while($timer.Elapsed.TotalSeconds -lt $deadline)
 throw "Deadline: $label; raw capture retained"
}
function Game($opcode,$level) {
 $script:held=0;$script:request++
 $null=Post '/api/game' @{token=$boot.token;client=$client;opcode=$opcode;level=$level;request_id=$script:request}
 Wait { $state.game -and $state.game.request_id -eq $request -and $state.game.state -eq 'applied' -and !$state.stale } 2.5 "$opcode level $level ACK plus snapshot"
 $flags=$state.telemetry.raw.status_flags
 if($opcode -eq 'start') {
  if(($flags -band 1024) -or $state.telemetry.raw.requested_sprites -ne (64 -shl ($level-1))) {throw 'Applied START state disagrees with board'}
 } elseif(!($flags -band 1024) -or $state.telemetry.raw.requested_sprites -ne 0 -or ($flags -band 65536)) {throw 'MENU workload/timing invalid'}
 [IO.File]::AppendAllText("$outPath/transitions.log","$opcode,level=$level,request=$request,session=$($state.session),snapshot=$($state.telemetry.sequence),floor=$($state.game.snapshot_floor),result=$($state.game.result)`n")
}
try {
 $serial.Open();$serial.DiscardInBuffer()
 if($LoadBit) {
  $bitPath=(Resolve-Path -LiteralPath $Bit).Path
  & D:/efinity/pgm/bin/ftdi_pgm.bat $bitPath -m jtag
  if($LASTEXITCODE -ne 0) {throw 'JTAG BIT failed'}
  Start-Sleep -Seconds 3
 }
 Push-Location 'D:/efinity_builds/competition_day1_20260906/sapphire/soc/bsp/efinix/EfxSapphireSoc/openocd'
 try {
  & D:/efinity/risc_v_gcc/openocd/bin/openocd.exe -f ftdi_ti.cfg -f debug_ti.cfg -c "init; reset halt; load_image {$binPath} 0x1000 bin; resume 0x1000; shutdown"
  if($LASTEXITCODE -ne 0) {throw 'JTAG firmware failed'}
 } finally {Pop-Location}
 $null=Post '/api/control' @{token=$boot.token;client=$client;keys=0;action_sequence=0;release=$false}
 $acquired=$true
 # Explicit HELLO before waiting for telemetry: a same-build hot reload resets
 # snapshot_id; only a fresh session ACK permits the gateway to rebase it.
 Wait { $tail -match 'V3_READY,build=20261008.*mode=MENU' -and !$state.stale -and $state.acknowledged -and $state.telemetry.session -eq $state.session -and $state.telemetry.raw.firmware_build_id -eq 0x20261008 -and ($state.telemetry.raw.status_flags -band 3072) -eq 3072 } 90 'new MENU startup'
 Wait {$state.acknowledged -and !$state.stale -and $state.telemetry.session -eq $state.session} 3 'control ownership ACK'
 foreach($level in 1..4) {
  Game 'start' $level
  $until=$timer.Elapsed.TotalSeconds+.8
  while($timer.Elapsed.TotalSeconds -lt $until) {Tick}
  Game 'menu' 0
 }
 'PASS real four-tier START/MENU ACK+snapshot. Movement/death/visual/replay still need separate evidence.'
} finally {
 if($acquired) {
  try {$null=Post '/api/control' @{token=$boot.token;client=$client;keys=0;action_sequence=$action;release=$true}} catch {Write-Warning 'Release failed; board lease expires in 250ms'}
 }
 if($serial.IsOpen) {$serial.Close()};$serial.Dispose()
 Get-FileHash -LiteralPath $binPath | Format-List | Out-File "$outPath/bin-hash.txt"
 if($LoadBit) {Get-FileHash -LiteralPath $Bit | Format-List | Out-File "$outPath/bit-hash.txt"}
}
