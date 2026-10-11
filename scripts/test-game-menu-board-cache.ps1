# Execute the board script's actual Game/Wait functions with network-only fixtures.
# No serial, JTAG or gateway requests are made by this regression.
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'test-game-menu-board.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
foreach($name in @('Game','Wait')) {
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
