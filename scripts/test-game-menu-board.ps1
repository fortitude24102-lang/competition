param(
 [Parameter(Mandatory=$true)][string]$Bin,
 [string]$Bit,
 [string]$GatewayUrl='http://127.0.0.1:8765',
 [ValidatePattern('^COM[1-9][0-9]*$')][string]$SerialPort='COM13',
 [Parameter(Mandatory=$true)][string]$OutDirectory,
 [switch]$LoadBit,
 [uint32]$ExpectedBuild=0x20261008,
 [switch]$PerformanceChallenge,
 [ValidateSet(4,6)][int]$LevelCount=4,
 [string]$Python='python'
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
$serial=New-Object IO.Ports.SerialPort $SerialPort,115200,'None',8,'One'
$serial.ReadTimeout=100
$client=[guid]::NewGuid().ToString('N');$held=0;$action=0;$request=0;$acquired=$false
$timer=[Diagnostics.Stopwatch]::StartNew();$lastKey=-1000.0;$lastStatus=-1000.0;$state=$null;$tail=''
$keepalive=$null;[uint32]$challengeSession=0
function Start-GameKeepalive {
 if($script:keepalive -or !$script:acquired -or $script:held) {throw 'Keepalive requires the existing neutral collector owner'}
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=(Get-Command $Python -CommandType Application -ErrorAction Stop).Source
 $info.Arguments='-u "'+(Join-Path $PSScriptRoot 'control-keepalive.py')+'"'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $script:keepalive=New-Object Diagnostics.Process
 $script:keepalive.StartInfo=$info
 if(!$script:keepalive.Start()) {throw 'Keepalive process did not start'}
 # Token goes through a private pipe, never process arguments or logs.
 $config=@{url=$GatewayUrl;body=@{token=$boot.token;client=$client;keys=0;action_sequence=$action;release=$false}}
 $script:keepalive.StandardInput.WriteLine(($config|ConvertTo-Json -Depth 3 -Compress))
 $script:keepalive.StandardInput.Flush()
}
function Stop-GameKeepalive {
 if(!$script:keepalive) {return}
 $child=$script:keepalive
 try {
  try {$child.StandardInput.Close()} catch {}
  if(!$child.WaitForExit(2000)) {$child.Kill();$child.WaitForExit()}
  ("KEEPALIVE_EXIT,code="+$child.ExitCode+"`n"+$child.StandardOutput.ReadToEnd()+$child.StandardError.ReadToEnd()) |
   Out-File "$outPath/keepalive.log" -Encoding utf8
 } finally {$child.Dispose();$script:keepalive=$null}
}
function Assert-ChallengeContinuity($snapshot,[uint32]$session) {
 if(!$snapshot.stale -and ($snapshot.session -ne $session -or
    ($snapshot.telemetry.raw.status_flags -band 0x3000) -ne 0x3000 -or
    ($snapshot.telemetry.raw.status_flags -band 1024))) {
  throw 'Challenge control session interrupted; raw capture retained, no qualification claimed'
 }
}
function Assert-QualifiedPerformance($snapshot,[uint32]$session,[uint32]$best) {
 if(!$snapshot -or $snapshot.stale -or !$snapshot.owned -or !$snapshot.acknowledged -or
    $snapshot.session -ne $session -or $snapshot.telemetry.session -ne $session -or
    !$snapshot.performance -or $snapshot.performance.stale -or $snapshot.performance.session -ne $session -or
    !$best -or $snapshot.performance.best -ne $best -or $snapshot.performance.frames -ne 3600 -or
    $snapshot.performance.stage -notin 4,5) {
  throw 'Final qualification is missing/stale/interrupted; raw capture retained, no qualification claimed'
 }
 Assert-ChallengeContinuity $snapshot $session
}
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
 if($script:keepalive -and $script:keepalive.HasExited) {throw 'Independent collector heartbeat stopped; raw capture retained'}
 if($script:acquired -and $timer.Elapsed.TotalMilliseconds-$script:lastKey -ge 70) {
  $null=Post '/api/control' @{token=$boot.token;client=$client;keys=$script:held;action_sequence=$script:action;release=$false}
  $script:lastKey=$timer.Elapsed.TotalMilliseconds
 }
 if($timer.Elapsed.TotalMilliseconds-$script:lastStatus -ge 100) {
  $script:state=Invoke-RestMethod "$GatewayUrl/api/status" -TimeoutSec 1
  [IO.File]::AppendAllText("$outPath/http.jsonl",($script:state|ConvertTo-Json -Depth 8 -Compress)+"`n")
  $script:lastStatus=$timer.Elapsed.TotalMilliseconds
  if($script:challengeSession) {Assert-ChallengeContinuity $script:state $script:challengeSession}
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
 # Do not let Wait accept an applied request cached before this POST/session.
 $script:state=$null;$script:lastStatus=-1000.0
 Wait { $state.game -and $state.game.request_id -eq $request -and $state.game.state -eq 'applied' -and !$state.stale } 2.5 "$opcode level $level ACK plus snapshot"
 $flags=$state.telemetry.raw.status_flags
 if($opcode -eq 'start') {
  $expectedCounts=@(64,128,256,512,786,1024)
  if(($flags -band 1024) -or $state.telemetry.raw.requested_sprites -ne $expectedCounts[$level-1]) {throw 'Applied START state disagrees with board'}
 } elseif($opcode -eq 'performance') {
  if(($flags -band 0x3000) -ne 0x3000 -or ($flags -band 1024)) {throw 'Performance entry capability/phase invalid'}
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
 $readyPattern='V3_READY,build='+$ExpectedBuild.ToString('x')+'.*mode=MENU'
 Wait { $tail -match $readyPattern -and !$state.stale -and $state.acknowledged -and $state.telemetry.session -eq $state.session -and $state.telemetry.raw.firmware_build_id -eq $ExpectedBuild -and ($state.telemetry.raw.status_flags -band 3072) -eq 3072 } 90 'new MENU startup'
 Wait {$state.acknowledged -and !$state.stale -and $state.telemetry.session -eq $state.session} 3 'control ownership ACK'
 if($LevelCount -eq 6 -and !($state.telemetry.raw.status_flags -band 0x4000)){throw 'Board does not advertise six game tiers'}
 foreach($level in 1..$LevelCount) {
  Game 'start' $level
  $until=$timer.Elapsed.TotalSeconds+.8
  while($timer.Elapsed.TotalSeconds -lt $until) {Tick}
  Game 'menu' 0
 }
 if($PerformanceChallenge) {
  if(!($state.telemetry.raw.status_flags -band 0x1000)) {throw 'Board does not advertise performance capability'}
  Game 'performance' 0
  # A retired owner cannot pass a qualification to the next HELLO session.
  $retiredSession=$state.session
  $null=Post '/api/control' @{token=$boot.token;client=$client;keys=0;action_sequence=$action;release=$true}
  $acquired=$false
  Wait { !$state.stale -and ($state.telemetry.raw.status_flags -band 1024) -and !$state.performance } 3 'lease loss returns challenge to MENU'
  $null=Post '/api/control' @{token=$boot.token;client=$client;keys=0;action_sequence=$action;release=$false}
  $acquired=$true;$lastKey=$timer.Elapsed.TotalMilliseconds
  Wait { !$state.stale -and $state.acknowledged -and $state.session -ne $retiredSession -and $state.telemetry.session -eq $state.session } 3 'new owner ACK'
  Game 'performance' 0
  Wait { !$state.stale -and $state.telemetry.raw.simulation_tick -ge 30 } 3 'first cohort advances before reset'
  $resetTick=$state.telemetry.raw.simulation_tick
  $action++;$held=64
  $until=$timer.Elapsed.TotalSeconds+.12;while($timer.Elapsed.TotalSeconds -lt $until) {Tick}
  $held=0
  Wait { !$state.stale -and $state.telemetry.raw.simulation_tick -lt $resetTick -and
   $state.performance -and !$state.performance.best -and $state.performance.target -eq 64 } 3 'R clears run and score'
  [IO.File]::AppendAllText("$outPath/transitions.log","PASS challenge lease retirement/new session/R reset`n")
  $challengeSession=[uint32]$state.session
  Start-GameKeepalive
  Wait { !$state.stale -and $state.performance -and !$state.performance.stale -and $state.performance.stage -ge 4 } 900 'automatic search and full3600 verification'
  if($state.performance.stage -eq 6 -or !$state.performance.best -or $state.performance.frames -ne 3600) {throw 'Challenge did not produce a qualified full3600 result'}
  $verifiedBest=$state.performance.best
  $stableUntil=$timer.Elapsed.TotalSeconds+5
  while($timer.Elapsed.TotalSeconds -lt $stableUntil) {
   Tick
   if(!$state.stale -and $state.performance -and !$state.performance.stale -and
       ($state.performance.stage -notin 4,5 -or $state.performance.best -ne $verifiedBest)) {throw 'Qualification invalidated after completion'}
  }
  Assert-QualifiedPerformance $state $challengeSession $verifiedBest
  $state|ConvertTo-Json -Depth 8 | Out-File "$outPath/performance-final.json" -Encoding utf8
  "PASS real performance: best=$($state.performance.best),stage=$($state.performance.stage),frames=$($state.performance.frames)"
  $challengeSession=0
  Game 'menu' 0
  Wait { !$state.performance } 2 'old challenge result cleared on MENU'
  Wait { $tail -match 'PERF_RESULT,.*frames=3600' } 2 'final counters emitted outside timed workload'
 }
 "PASS real $LevelCount-tier START/MENU ACK+snapshot. Movement/death/visual/replay still need separate evidence."
} finally {
 $challengeSession=0
 try {Stop-GameKeepalive} finally {
  if($acquired) {
   try {$null=Post '/api/control' @{token=$boot.token;client=$client;keys=0;action_sequence=$action;release=$true}} catch {Write-Warning 'Release failed; board lease expires in 250ms'}
  }
  if($serial.IsOpen) {$serial.Close()};$serial.Dispose()
  Get-FileHash -LiteralPath $binPath | Format-List | Out-File "$outPath/bin-hash.txt"
  if($LoadBit) {Get-FileHash -LiteralPath $Bit | Format-List | Out-File "$outPath/bit-hash.txt"}
 }
}
