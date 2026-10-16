# Execute the board script's actual Game/Wait functions with network-only fixtures.
# No serial, JTAG or gateway requests are made by this regression.
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'test-game-menu-board.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
foreach($name in @('Game','Wait','Assert-ChallengeContinuity','Assert-QualifiedPerformance')) {
 $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 if(!$function) {throw "Missing actual function: $name"}
 . ([scriptblock]::Create($function.Extent.Text))
}
$timer=[Diagnostics.Stopwatch]::StartNew();$lastStatus=$timer.Elapsed.TotalMilliseconds
$held=0;$request=0;$boot=@{token='offline-fixture'};$client='offline-fixture'
$outPath=Join-Path ([IO.Path]::GetTempPath()) ('game-menu-cache-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $outPath | Out-Null
# A completed request from the previous session, followed by a fresh MENU snapshot.
$state=@{stale=$false;game=@{request_id=1;state='applied'};telemetry=@{raw=@{status_flags=1024;requested_sprites=0}}}
$polls=0
function Post($path,$body) {return @{accepted=$true;game=@{request_id=1;state='pending'}}}
function Tick {
 $script:polls++
 if($timer.Elapsed.TotalMilliseconds-$script:lastStatus -ge 100) {
  $script:state=@{stale=$false;session=42;game=@{request_id=1;state='applied';result=0;snapshot_floor=2};telemetry=@{sequence=3;raw=@{status_flags=0;requested_sprites=64}}}
  $script:lastStatus=$timer.Elapsed.TotalMilliseconds
 }
}
Game 'start' 1
if($polls -ne 1 -or $state.telemetry.raw.requested_sprites -ne 64) {throw 'New game must poll fresh state before accepting an old cached completion'}
'PASS actual Game/Wait rejects cached prior-session completion by refreshing status after POST'
Assert-ChallengeContinuity @{stale=$false;session=42;telemetry=@{raw=@{status_flags=0x3000}}} 42
Assert-ChallengeContinuity @{stale=$true;session=43;telemetry=@{raw=@{status_flags=1024}}} 42
foreach($bad in @(
 @{stale=$false;session=43;telemetry=@{raw=@{status_flags=0x3000}}},
 @{stale=$false;session=42;telemetry=@{raw=@{status_flags=1024}}},
 @{stale=$false;session=42;telemetry=@{raw=@{status_flags=0}}}
)) {
 $failed=$false
 try {Assert-ChallengeContinuity $bad 42} catch {$failed=$true}
 if(!$failed){throw 'Interrupted challenge must fail instead of waiting900s or reusing its score'}
}
'PASS challenge collector rejects new sessions/MENU/non-performance state without weakening any lease'
function QualifiedSnapshot {
 return @{stale=$false;owned=$true;acknowledged=$true;session=42;
  performance=@{stale=$false;session=42;best=1040;frames=3600;stage=4};
  telemetry=@{session=42;raw=@{status_flags=0x3000}}}
}
Assert-QualifiedPerformance (QualifiedSnapshot) 42 1040
foreach($case in @('missing','stale','no_performance','stale_performance','session','perf_session','telemetry_session','unowned','unacknowledged','frames','best','stage')) {
 $snapshot=QualifiedSnapshot
 switch($case) {
  'missing' {$snapshot=$null}
  'stale' {$snapshot.stale=$true}
  'no_performance' {$snapshot.performance=$null}
  'stale_performance' {$snapshot.performance.stale=$true}
  'session' {$snapshot.session=43}
  'perf_session' {$snapshot.performance.session=43}
  'telemetry_session' {$snapshot.telemetry.session=43}
  'unowned' {$snapshot.owned=$false}
  'unacknowledged' {$snapshot.acknowledged=$false}
  'frames' {$snapshot.performance.frames=3599}
  'best' {$snapshot.performance.best=0}
  'stage' {$snapshot.performance.stage=6}
 }
 $failed=$false
 try {Assert-QualifiedPerformance $snapshot 42 1040} catch {$failed=$true}
 if(!$failed) {throw "Invalid final qualification accepted: $case"}
}
'PASS final qualification requires fresh full3600 score and the same acknowledged owner/session'
$cleanup=$ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]} | Select-Object -Last 1
$serial=[pscustomobject]@{IsOpen=$false;disposed=$false}
$serial | Add-Member ScriptMethod Dispose {$this.disposed=$true}
$acquired=$false;$LoadBit=$false;$binPath=$source
function Stop-GameKeepalive {throw 'injected heartbeat cleanup failure'}
$failed=$false
try {. ([scriptblock]::Create(($cleanup.Finally.Statements.Extent.Text -join "`n")))} catch {$failed=$true}
if(!$failed -or !$serial.disposed -or !(Test-Path "$outPath/bin-hash.txt")) {
 throw 'Heartbeat cleanup failure must still dispose serial and preserve firmware identity'
}
'PASS collector cleanup preserves serial disposal and identity even if heartbeat cleanup fails'
