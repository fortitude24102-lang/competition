param([string]$Out='generated/verification/v3/board-control-20261005',[switch]$Replay,[switch]$HoldAcrossReplay)
# Uses the already running candidate. No bitstream, firmware or Flash writes.
$ErrorActionPreference='Stop'
if(Test-Path "$Out.serial.log") {throw 'Refusing to overwrite board evidence'}
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$url='http://127.0.0.1:8765'
$token=(Invoke-RestMethod "$url/api/bootstrap").token
$client=[Guid]::NewGuid().ToString('N')
$serial=New-Object IO.Ports.SerialPort 'COM13',115200,'None',8,'One'
$script:received=''
$script:lastStatus=0
$timer=[Diagnostics.Stopwatch]::StartNew()
function Capture {
 $chunk=$serial.ReadExisting()
 if($chunk) {
  $script:received+=$chunk
  [IO.File]::AppendAllText("$Out.serial.log",$chunk)
  Write-Output $chunk
  if($script:received -match 'V3_FAIL') {throw 'Candidate reported V3_FAIL'}
 }
 if($timer.ElapsedMilliseconds-$script:lastStatus -ge 200) {
  $status=Invoke-RestMethod "$url/api/status"
  $entry=@{elapsed_ms=$timer.ElapsedMilliseconds;status=$status}|ConvertTo-Json -Depth 8 -Compress
  [IO.File]::AppendAllText("$Out.status.jsonl",$entry+"`n")
  $script:lastStatus=$timer.ElapsedMilliseconds
 }
}
function Keys([int]$held,[int]$action=0,[bool]$release=$false) {
 $body=@{token=$token;client=$client;keys=$held;action_sequence=$action;release=$release}|ConvertTo-Json -Compress
 $reply=Invoke-RestMethod "$url/api/control" -Method Post -ContentType 'application/json' -Headers @{Origin=$url} -Body $body
 if(!$reply.accepted) {throw 'Control ownership rejected'}
}
function Pump([int]$milliseconds,[int]$held=-1,[int]$action=0) {
 $end=$timer.ElapsedMilliseconds+$milliseconds
 while($timer.ElapsedMilliseconds -lt $end) {
  if($held -ge 0) {Keys $held $action}
  Capture
  Start-Sleep -Milliseconds 33
 }
}
try {
 $serial.Open()
 Pump 1200
 # A live game may already be GAME OVER. Verify movement from a fresh round,
 # not by changing gameplay's intentional death freeze. Action1 is restart.
 Pump 600 64 1
 Pump 100 0 1
 Pump 1500 2 1
 $status=Invoke-RestMethod "$url/api/status"
 if(!$status.acknowledged -or $status.simulated) {throw 'No real FPGA HELLO ACK'}
 Pump 1000 4 1
 # Deliberately stop browser heartbeats: latest keys must expire, not stick.
 $releaseOffset=$script:received.Length
 Pump 1500
 $released=$script:received.Substring($releaseOffset)
 if($released -notmatch 'keys=00000000,age=-1') {throw 'Expired input was not released on FPGA'}
 if($script:received -notmatch 'keys=00000002' -or $script:received -notmatch 'keys=00000004') {throw 'FPGA did not consume RIGHT/UP'}
 $positions=[regex]::Matches($script:received,'x=(\d+),y=(\d+)')
 if(($positions|ForEach-Object {$_.Groups[1].Value}|Sort-Object -Unique).Count -lt 2 -or
    ($positions|ForEach-Object {$_.Groups[2].Value}|Sort-Object -Unique).Count -lt 2) {throw 'RISC-V player position did not change'}
 Write-Output 'PASS actual HTTP -> UDP -> FPGA -> Sapphire input, telemetry ACK, movement, lease release'
 if($Replay) {
  $lastLive=[regex]::Matches($script:received,'V3_PERF,mode=0,tick=(\d+)')
  $liveTick=[uint32]$lastLive[$lastLive.Count-1].Groups[1].Value
  Pump 1500 128 2
  Keys 0 2 $true
  $deadline=$timer.Elapsed.TotalSeconds+420
  while($script:received -notmatch 'V3_REPLAY,GPU_DONE,frames=600,LIVE_RESTORED') {
   if($timer.Elapsed.TotalSeconds -ge $deadline) {throw '600 tick comparison deadline'}
   if($HoldAcrossReplay -and $script:received -match 'V3_REPLAY,CPU_DONE') {Keys 192 3}
   Capture
   Start-Sleep -Milliseconds 33
  }
  if($script:received -notmatch 'V3_REPLAY,CPU_DONE,crc=[0-9a-f]+,frames=600') {throw 'CPU replay incomplete'}
  if($HoldAcrossReplay) {
   Pump 1200 192 3
   $restored=$script:received.Substring($script:received.IndexOf('V3_REPLAY,GPU_DONE'))
   $last=[regex]::Matches($restored,'V3_PERF,mode=0,tick=(\d+)')
   if(!$last.Count -or [uint32]$last[$last.Count-1].Groups[1].Value -lt $liveTick) {throw 'Held R/C retriggered on LIVE restore'}
   Write-Output 'PASS held R/C action sequence preserved across LIVE restore'
  } else {Pump 1200}
  Write-Output 'PASS CPU/GPU each600 recorded tick replay and LIVE restore; not a high-load qualification'
 }
} finally {
 try {Keys 0 3 $true} catch {Write-Warning 'Gateway release failed; 250ms FPGA lease still applies'}
 if($serial.IsOpen) {$serial.Close()};$serial.Dispose()
}
